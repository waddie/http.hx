; Request text objects - treat entire HTTP request as a "function"
(request) @function.around

; Request body as function.inside
(request
  body: (_) @function.inside)

; If there's no body, the URL and headers section could be considered "inside"
; This captures the method + url + headers as an alternative inside
(request
  url: (target_url) @function.inside)

; Response text objects - also treat as "function"
(response) @function.around

(response
  body: (_) @function.inside)

; Section text objects - the top-level container
(section) @class.around

; Header text objects - individual headers as "parameters" or "arguments"
; Each header is a key-value pair, similar to function arguments
(header) @parameter.inside @parameter.around

; To select all headers as a block, we can't easily capture them as one unit
; in tree-sitter, but we can capture the request's header-containing region.
; This pattern captures each header individually for navigation.

; Comment text objects
(comment) @comment.inside

; Multiple consecutive comments as a block
(comment)+ @comment.around

; Variable declaration as parameter (since it's also a key-value pair)
(variable_declaration) @parameter.around

(variable_declaration
  value: (_) @parameter.inside)

; Script text objects (pre-request and response handler scripts)
(pre_request_script
  (script) @function.inside) @function.around

(res_handler_script
  (script) @function.inside) @function.around

; GraphQL body parts
(graphql_body
  (graphql_data) @function.inside) @function.around

; External body reference
(external_body) @parameter.around

; Variable references
(variable) @parameter.inside

; Value text objects (for header values, variable values, etc.)
; These can be useful for selecting just the value part
(header
  value: (value) @entry.inside)

; Target URL as an entry
(target_url) @entry.around

; Method as entry
(method) @entry.around
