(define package-name 'http.hx)
(define version "0.3.0")
(define dependencies
  '((#:name http2curl
     #:git-url
     "https://github.com/waddie/http2curl.scm"
     #:sha
     "c39d83164a6a170e1cfdc3fcc09c76ee5a2f6a2a")
    (#:name run-command
     #:git-url
     "https://github.com/waddie/run-command.scm"
     #:sha
     "ed42a376c4761e10530981c34797e7dde8e5abef")))
