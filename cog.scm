(define package-name 'http.hx)
(define version "0.2.0")
(define dependencies
  '((#:name http2curl
     #:git-url
     "https://github.com/waddie/http2curl.scm")
    (#:name run-command
     #:git-url
     "https://github.com/waddie/run-command.scm")))
