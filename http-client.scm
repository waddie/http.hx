#!/usr/bin/env steel

;; SPDX-License-Identifier: AGPL-3.0-or-later
;; Copyright (C) 2025 Wade Garrison
;;
;; This file is part of http.hx.
;;
;; http.hx is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; http.hx is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU Affero General Public License for more details.
;;
;; You should have received a copy of the GNU Affero General Public License
;; along with http.hx. If not, see <https://www.gnu.org/licenses/>.

;;; http.hx - HTTP client plugin for Helix editor
;;;
;;; This plugin executes HTTP requests from .http buffers using vscode-restclient
;;; syntax. It converts requests to curl commands via http2curl.scm and displays
;;; responses in a persistent *http* scratch buffer.

;; ============================================================================
;; Dependencies
;; ============================================================================

(require (prefix-in http2curl: "./cogs/http2curl.scm"))
(require-builtin steel/process)
(require-builtin steel/time)
(require-builtin helix/core/text as text.)
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/editor.scm")
(require "helix/misc.scm")

;; ============================================================================
;; State Management
;; ============================================================================

;; HTTP client state structure
(struct http-state
        (buffer-id ; DocumentId - persistent *http* scratch buffer
         timeout-ms ; Number - curl execution timeout in milliseconds
         orientation ; Symbol - 'vsplit or 'hsplit
         include-headers? ; Boolean - include response headers in output
         request-count) ; Number - counter for request numbering
  #:transparent)

;; Global state (boxed for mutability)
(define *http-state* (box #f))

;; Initialize default state
(define (init-http-state!)
  "Initialize default http-state if not exists"
  (when (not (unbox *http-state*))
    (set-box! *http-state*
              (http-state #f ; buffer-id
                          30000 ; timeout-ms (30 seconds)
                          'vsplit ; orientation
                          #t ; include-headers?
                          0)))) ; request-count

;; Get current state (initializes if needed)
(define (get-state)
  "Get current http-state, initializing if necessary"
  (init-http-state!)
  (unbox *http-state*))

;; Update state
(define (set-state! new-state)
  "Update global http-state"
  (set-box! *http-state* new-state))

;; ============================================================================
;; Buffer Management
;; ============================================================================

;; Ensure *http* scratch buffer exists and is visible
(define (http:ensure-buffer)
  "Create or get existing *http* scratch buffer
   Returns: updated state"
  (let* ([state (get-state)]
         [doc-id (http-state-buffer-id state)]
         [orientation (http-state-orientation state)])

    ;; Check if buffer exists and is visible
    (if (and doc-id (editor-doc-exists? doc-id) (editor-doc-in-view? doc-id))
        ;; Buffer exists and visible - return current state
        state

        ;; Create new buffer
        (let* ([original-view (editor-focus)]
               ;; Split based on orientation
               [_ (if (equal? orientation 'vsplit)
                      (helix.vsplit)
                      (helix.hsplit))]
               ;; Create new buffer
               [_ (helix.new)]
               [new-view (editor-focus)]
               [new-doc-id (editor->doc-id new-view)]
               ;; Configure scratch buffer
               [_ (set-scratch-buffer-name! "*http*")]
               [_ (helix.set-language "markdown")]
               ;; Update state with new buffer-id
               [new-state (http-state new-doc-id
                                      (http-state-timeout-ms state)
                                      (http-state-orientation state)
                                      (http-state-include-headers? state)
                                      (http-state-request-count state))])
          (set-state! new-state)
          ;; Return to original view
          (editor-set-focus! original-view)
          new-state))))

;; Append text to *http* buffer
(define (http:append-to-buffer text)
  "Append text to *http* scratch buffer"
  (let* ([state (http:ensure-buffer)]
         [doc-id (http-state-buffer-id state)]
         [current-view (editor-focus)]
         [buffer-view (editor-doc-in-view? doc-id)])

    ;; Switch to *http* buffer if it's in view
    (when buffer-view
      (editor-set-focus! buffer-view)

      ;; Move to end and append text
      (helix.static.select_all)
      (helix.static.collapse_selection)
      (helix.static.insert_string text)
      (helix.static.align_view_bottom)

      ;; Return to original view
      (editor-set-focus! current-view))

    state))

;; Clear *http* buffer contents
(define (http:clear-buffer)
  "Clear *http* scratch buffer contents"
  (let* ([state (http:ensure-buffer)]
         [doc-id (http-state-buffer-id state)]
         [current-view (editor-focus)]
         [buffer-view (editor-doc-in-view? doc-id)])

    ;; Switch to *http* buffer if it's in view
    (when buffer-view
      (editor-set-focus! buffer-view)
      (helix.static.select_all)
      (helix.static.insert_string "")
      (editor-set-focus! current-view))

    state))

;; ============================================================================
;; Utility Functions
;; ============================================================================

;; String utility: split string on first occurrence of delimiter
(define (split-once str delimiter)
  "Split string on first occurrence of delimiter, return (cons left right) or #f"
  (let ([parts (split-many str delimiter)])
    (if (>= (length parts) 2)
        (cons (car parts) (string-join (cdr parts) delimiter))
        #f)))

;; String utility: check if string starts with prefix
(define (starts-with? str prefix)
  "Check if string starts with prefix"
  (and (>= (string-length str) (string-length prefix))
       (equal? (substring str 0 (string-length prefix)) prefix)))

;; Note: string-contains? is a built-in Steel function, no need to define it

;; ============================================================================
;; Variable Extraction
;; ============================================================================

;; Extract @variable = value declarations from buffer
(define (http:extract-file-variables buffer-text)
  "Extract @variable = value declarations from buffer text
   Returns: association list '((\"var1\" . \"value1\") (\"var2\" . \"value2\"))"
  (let* ([lines (split-many buffer-text "\n")]
         [var-pattern (lambda (line)
                        (let ([trimmed (trim line)])
                          (if (starts-with? trimmed "@")
                              (let* ([without-at (substring trimmed 1 (string-length trimmed))]
                                     [parts (split-once without-at "=")])
                                (if parts
                                    (cons (trim (car parts)) (trim (cdr parts)))
                                    #f))
                              #f)))])
    (filter (lambda (x) x) (map var-pattern lines))))

;; ============================================================================
;; Selection Handling
;; ============================================================================

;; Get text of primary selection
(define (http:get-primary-selection)
  "Get text of primary selection"
  (helix.static.current-highlighted-text!))

;; Get list of text from all selections
(define (http:get-all-selections)
  "Get list of text from all selections, return (listof string)"
  (let* ([doc-id (editor->doc-id (editor-focus))]
         [rope (editor->text doc-id)]
         [full-text (text.rope->string rope)]
         [selection-obj (helix.static.current-selection-object)]
         [ranges (helix.static.selection->ranges selection-obj)])
    (map (lambda (range)
           (let* ([from (helix.static.range->from range)]
                  [to (helix.static.range->to range)]
                  [slice (text.rope->slice rope from to)])
             (text.rope->string slice)))
         ranges)))

;; Get entire buffer text
(define (http:get-buffer-text)
  "Get entire buffer text"
  (let* ([doc-id (editor->doc-id (editor-focus))]
         [rope (editor->text doc-id)])
    (text.rope->string rope)))

;; ============================================================================
;; Curl Execution
;; ============================================================================

;; Execute curl command with timeout using shell
(define (http:run-curl-with-timeout curl-cmd-str timeout-ms)
  "Execute curl command string with timeout via /bin/sh -c
   curl-cmd-str: string - complete curl command (e.g., 'curl -i https://...')
   timeout-ms: number - timeout in milliseconds
   Returns: Result<String> - Ok with stdout or Err with error message"
  (with-handler (lambda (err) (Err (string-append "Curl execution failed: " (to-string err))))
                (let* ([cmd (command "/bin/sh" (list "-c" curl-cmd-str))]
                       [_ (set-piped-stdout! cmd)] ; Pipes stdout, stderr, and stdin
                       [child-result (spawn-process cmd)])

                  (if (Err? child-result)
                      (Err (string-append "Failed to spawn curl: "
                                          (to-string (Err->value child-result))))

                      (let* ([child (Ok->value child-result)]
                             [timed-out? (box #f)]
                             [result-box (box #f)]

                             ;; Spawn timeout thread
                             [timeout-thread (spawn-native-thread (lambda ()
                                                                    (time/sleep-ms timeout-ms)
                                                                    (when (not (unbox result-box))
                                                                      (set-box! timed-out? #t)
                                                                      (kill child))))]

                             ;; Wait for result
                             [output-result (wait->stdout child)])

                        ;; Mark as complete
                        (set-box! result-box #t)

                        ;; Check if timed out
                        (if (unbox timed-out?)
                            (Err (string-append "Request timed out after "
                                                (number->string (/ timeout-ms 1000))
                                                " seconds"))
                            output-result))))))

;; Execute curl command
(define (http:execute-curl-command curl-cmd-str state)
  "Execute curl command string with configured timeout
   curl-cmd-str: string - curl command
   state: http-state - current state (for timeout)
   Returns: Result<String> - Ok with output or Err with error message"
  (let ([timeout-ms (http-state-timeout-ms state)])
    (http:run-curl-with-timeout curl-cmd-str timeout-ms)))

;; ============================================================================
;; Response Parsing and Formatting
;; ============================================================================

;; Extract Content-Type from response headers
(define (http:extract-content-type headers)
  "Extract Content-Type from response headers"
  (let* ([lines (split-many headers "\n")]
         [ct-line (filter (lambda (line) (starts-with? (string-downcase (trim line)) "content-type:"))
                          lines)])
    (if (not (null? ct-line))
        (let* ([line (car ct-line)]
               [parts (split-once line ":")]
               [value (if parts
                          (trim (cdr parts))
                          "")])
          ;; Extract just the media type, ignore charset
          (let ([semicolon-parts (split-many value ";")]) (trim (car semicolon-parts))))
        "text/plain")))

;; Map Content-Type to code block language
(define (http:content-type->lang content-type)
  "Map Content-Type to code block language for syntax highlighting"
  (let ([ct (string-downcase content-type)])
    (cond
      [(string-contains? ct "json") "json"]
      [(string-contains? ct "xml") "xml"]
      [(string-contains? ct "html") "html"]
      [(string-contains? ct "javascript") "javascript"]
      [(string-contains? ct "css") "css"]
      [(string-contains? ct "yaml") "yaml"]
      [else "text"])))

;; Parse curl output into headers and body
(define (http:parse-curl-output output include-headers?)
  "Parse curl output into headers and body
   Returns: hash with 'headers, 'body, and 'lang keys"
  (if include-headers?
      ;; Parse headers and body (separated by \r\n\r\n)
      (let* ([separator "\r\n\r\n"]
             [parts (split-once output separator)])
        (if parts
            (let* ([headers (car parts)]
                   [body (cdr parts)]
                   [content-type (http:extract-content-type headers)]
                   [lang (http:content-type->lang content-type)])
              (hash 'headers headers 'body body 'lang lang))
            ;; No separator found - treat all as body
            (hash 'headers "" 'body output 'lang "text")))

      ;; No headers requested - all is body
      (hash 'headers #f 'body output 'lang "text")))

;; Format response for display in Markdown
(define (http:format-response request-num curl-cmd parsed-response)
  "Format response for display in Markdown buffer
   request-num: Number - request counter
   curl-cmd: String - the curl command that was executed
   parsed-response: Hash - result from http:parse-curl-output
   Returns: String - formatted Markdown"
  (let* ([headers (hash-ref parsed-response 'headers)]
         [body (hash-ref parsed-response 'body)]
         [lang (hash-ref parsed-response 'lang)]
         [separator "---\n\n"])

    (string-append "## Request "
                   (number->string request-num)
                   "\n\n```bash\n"
                   curl-cmd
                   "\n```\n\n"
                   "### Response\n\n"
                   (if (and headers (not (equal? headers "")))
                       (string-append "**Headers:**\n```http\n" headers "\n```\n\n**Body:**\n")
                       "")
                   "```"
                   lang
                   "\n"
                   body
                   "\n```\n\n"
                   separator)))

;; ============================================================================
;; Configuration Commands
;; ============================================================================

;;@doc
;; Set timeout for curl execution
(define (http-set-timeout . args)
  "Set or show timeout for HTTP request execution
   Usage: :http-set-timeout [seconds]
   Without args: shows current timeout
   With args: sets timeout to specified seconds"
  (let ([state (get-state)])
    (if (null? args)
        ;; Show current timeout
        (helix.echo (string-append "Current timeout: "
                                   (number->string (/ (http-state-timeout-ms state) 1000))
                                   " seconds"))
        ;; Set new timeout
        (let* ([input (car args)]
               [seconds (string->number input)])
          (if seconds
              (let ([timeout-ms (* seconds 1000)])
                (set-state! (http-state (http-state-buffer-id state)
                                        timeout-ms
                                        (http-state-orientation state)
                                        (http-state-include-headers? state)
                                        (http-state-request-count state)))
                (helix.echo (string-append "Timeout set to " (number->string seconds) " seconds")))
              (helix.echo "Error: Invalid number"))))))

;;@doc
;; Set scratch buffer orientation
(define (http-set-orientation . args)
  "Set or show scratch buffer split orientation
   Usage: :http-set-orientation [vsplit|hsplit|v|h|vertical|horizontal]
   Without args: shows current orientation
   With args: sets orientation"
  (let ([state (get-state)])
    (if (null? args)
        ;; Show current orientation
        (helix.echo (string-append "Current orientation: "
                                   (symbol->string (http-state-orientation state))))
        ;; Set new orientation
        (let* ([arg (car args)]
               [orientation
                (cond
                  [(or (equal? arg "vsplit") (equal? arg "v") (equal? arg "vertical")) 'vsplit]
                  [(or (equal? arg "hsplit") (equal? arg "h") (equal? arg "horizontal")) 'hsplit]
                  [else #f])])
          (if orientation
              (begin
                (set-state! (http-state (http-state-buffer-id state)
                                        (http-state-timeout-ms state)
                                        orientation
                                        (http-state-include-headers? state)
                                        (http-state-request-count state)))
                (helix.echo (string-append "Orientation set to " (symbol->string orientation))))
              (helix.echo "Error: Use vsplit/v/vertical or hsplit/h/horizontal"))))))

;;@doc
;; Toggle response header inclusion
(define (http-toggle-headers)
  "Toggle inclusion of response headers in output
   Usage: :http-toggle-headers"
  (let* ([state (get-state)]
         [current (http-state-include-headers? state)]
         [new-val (not current)])
    (set-state! (http-state (http-state-buffer-id state)
                            (http-state-timeout-ms state)
                            (http-state-orientation state)
                            new-val
                            (http-state-request-count state)))
    (helix.echo (string-append "Response headers: " (if new-val "enabled" "disabled")))))

;; ============================================================================
;; Main Execution Flow
;; ============================================================================

;; Execute HTTP requests
(define (http:execute-requests selections variables)
  "Main execution function
   selections: (listof string) - HTTP request texts
   variables: (listof (cons string string)) - variable bindings
   Returns: Result<String> - Ok with formatted output or Err with error message"
  (with-handler
   (lambda (err) (Err (string-append "Execution error: " (to-string err))))
   (let* ([state (get-state)]
          [include-headers? (http-state-include-headers? state)]

          ;; Convert to curl commands via http2curl
          [curl-cmds (http2curl:http->curl selections variables #:include-headers? include-headers?)]

          ;; Execute each curl command
          [results (map (lambda (curl-cmd) (http:execute-curl-command curl-cmd state)) curl-cmds)]

          ;; Check for errors
          [errors (filter Err? results)])

     (if (not (null? errors))
         ;; Return first error
         (car errors)

         ;; Format all responses
         (let* ([outputs (map Ok->value results)]
                [parsed (map (lambda (output) (http:parse-curl-output output include-headers?))
                             outputs)]
                [formatted (map (lambda (idx)
                                  (let ([request-num (+ (http-state-request-count state) idx 1)]
                                        [curl-cmd (list-ref curl-cmds idx)]
                                        [response (list-ref parsed idx)])
                                    (http:format-response request-num curl-cmd response)))
                                (range 0 (length parsed)))]
                [combined (apply string-append formatted)]

                ;; Update request counter
                [new-state (http-state (http-state-buffer-id state)
                                       (http-state-timeout-ms state)
                                       (http-state-orientation state)
                                       (http-state-include-headers? state)
                                       (+ (http-state-request-count state) (length curl-cmds)))])

           (set-state! new-state)
           (Ok combined))))))

;; ============================================================================
;; Validation
;; ============================================================================

;; Validate selection is not empty
(define (http:validate-selection text)
  "Validate selection is not empty
   Returns: Result<String> - Ok with text or Err with error message"
  (if (or (not text) (equal? (trim text) ""))
      (Err "Selection is empty")
      (Ok text)))

;; Validate all selections
(define (http:validate-selections selections)
  "Validate all selections are not empty
   Returns: Result<(listof string)> - Ok with selections or Err with error message"
  (let* ([results (map http:validate-selection selections)]
         [errors (filter Err? results)])
    (if (not (null? errors))
        (Err "One or more selections are empty")
        (Ok selections))))

;; ============================================================================
;; User Commands
;; ============================================================================

;; Safe command wrapper
(define (safe-command command-fn)
  "Wrap command function with error handler"
  (lambda args
    (with-handler (lambda (err) (helix.echo (string-append "Error: " (to-string err))))
                  (apply command-fn args))))

;; Execute HTTP request in primary selection
(define (http-exec-selection-impl)
  "Execute HTTP request in primary selection (internal)"
  (let* ([selection-text (http:get-primary-selection)]
         [validation (http:validate-selection selection-text)])

    (if (Err? validation)
        (helix.echo (Err->value validation))
        (let* ([buffer-text (http:get-buffer-text)]
               [variables (http:extract-file-variables buffer-text)]
               [result (http:execute-requests (list selection-text) variables)])

          (if (Ok? result)
              (let ([output (Ok->value result)])
                (http:append-to-buffer output)
                (helix.echo "Request executed successfully"))
              (helix.echo (Err->value result)))))))

;; Execute HTTP requests in all selections
(define (http-exec-multiple-selections-impl)
  "Execute HTTP requests in all selections (internal)"
  (let* ([selections (http:get-all-selections)]
         [validation (http:validate-selections selections)])

    (if (Err? validation)
        (helix.echo (Err->value validation))
        (let* ([buffer-text (http:get-buffer-text)]
               [variables (http:extract-file-variables buffer-text)]
               [result (http:execute-requests selections variables)])

          (if (Ok? result)
              (let ([output (Ok->value result)])
                (http:append-to-buffer output)
                (helix.echo (string-append (number->string (length selections))
                                           " requests executed successfully")))
              (helix.echo (Err->value result)))))))

;; Execute all HTTP requests in buffer
(define (http-exec-buffer-impl)
  "Execute all HTTP requests in buffer (internal)"
  (let* ([buffer-text (http:get-buffer-text)]
         [validation (http:validate-selection buffer-text)])

    (if (Err? validation)
        (helix.echo "Buffer is empty")
        (let* ([variables (http:extract-file-variables buffer-text)]
               [result (http:execute-requests (list buffer-text) variables)])

          (if (Ok? result)
              (let ([output (Ok->value result)])
                (http:append-to-buffer output)
                (helix.echo "Buffer executed successfully"))
              (helix.echo (Err->value result)))))))

;; Wrap commands with error handling

;;@doc
;; Execute HTTP request in primary selection
(define http-exec-selection (safe-command http-exec-selection-impl))
;;@doc
;; Execute HTTP requests in all selections
(define http-exec-multiple-selections (safe-command http-exec-multiple-selections-impl))
;;@doc
;; Execute all HTTP requests in buffer
(define http-exec-buffer (safe-command http-exec-buffer-impl))

;; ============================================================================
;; Command Registration
;; ============================================================================

;; Register commands with Helix
(provide http-exec-selection
         http-exec-multiple-selections
         http-exec-buffer
         http-set-timeout
         http-set-orientation
         http-toggle-headers)
