(define package-name 'http.hx)
(define version "0.4.0")
(define dependencies
  '((#:name http2curl
     #:git-url
     "https://github.com/waddie/http2curl.scm"
     #:sha
     "4ede64e10213f4979aa3c4e2a818e328925540bb")
    (#:name run-command
     #:git-url
     "https://github.com/waddie/run-command.scm"
     #:sha
     "ed42a376c4761e10530981c34797e7dde8e5abef")))
