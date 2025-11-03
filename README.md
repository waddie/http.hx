# http.hx

A currently minimal HTTP client plugin for the Helix editor, based on the Visual Studio Code REST client syntax.

Parses the request into a `curl` command and runs that via shell, parsing the response to Markdown with appropriate injections.

I’ve only tested this on macOS. Linux should be no different, but I’ve no idea what it will do on Windows.

Currently you’ll need [mattwparas’s steel-event-system Helix fork](https://github.com/mattwparas/helix/tree/steel-event-system) to use this, and may want to check out his [helix-config](https://github.com/mattwparas/helix-config) repo to see how to set up key bindings, etc.

## Demo

![An asciinema recording of HTTP requests being executed in Helix](https://github.com/waddie/http.hx/blob/main/images/demo.gif?raw=true)

## Status

This is a work in progress, experimental plugin for a work in progress, experimental plugin system. It’s barely been tested. I wouldn’t necessarily advise firing HTTP requests at your production environment with this.

## Features

- Execute HTTP requests from `.http` files using `vscode-restclient` syntax
- Variable substitution with `@variable = value` declarations
- Persistent scratch buffer with Markdown formatting
- Syntax highlighting for response bodies (JSON, XML, HTML, etc.)
- Configurable timeout, split orientation, and header inclusion
- Support for multiple selections and batch execution

## Installation

You need to be running Helix with the experimental Steel plugin system. You’ll need `curl` installed and in your `PATH`.

1. Copy `http-client.scm` to your Helix configuration directory (e.g. `~/.config/helix/`)
2. Ensure `http2curl.scm` is available, e.g. in `./config/helix/cogs/http2curl.scm` (grab it from my [http2curl repo](https://github.com/waddie/http2curl.scm))
3. Load the plugin in Helix (e.g. add to `init.scm`, see below for an example)

Helix doesn’t ship with the http grammar by default. I built and installed the grammar and `highlight.scm` queries from [tree-sitter-http](https://github.com/rest-nvim/tree-sitter-http), then added this to my `languages.toml`:

```toml
[[language]]
name = "http"
scope = "source.http"
injection-regex = "(http)"
file-types = ["http"]
comment-token = "--"
indent = { tab-width = 2, unit = " " }
```

## Usage

### Basic Example

Create a `.http` file:

```http
# Simple GET request
GET https://httpbin.io/get

###

# POST with JSON body
POST https://httpbin.io/post
Content-Type: application/json

{
  "name": "http.hx",
  "version": "1.0"
}
```

Select a request and run `:http-exec-selection` to execute. Results appear in the `*http*` scratch buffer.

Note that when I say “select”, I really mean “select” the whole thing. It won’t work/do what you expect with your cursor somewhere in the request, like it would with similar plugins in other editors. I think this is in keeping with Helix’s selection-action model.

### Variable Substitution

```http
@baseUrl = https://api.example.com
@token = your-api-token

GET {{baseUrl}}/users
Authorization: Bearer {{token}}
```

### Commands

- `:http-exec-selection` - Execute HTTP request in primary selection
- `:http-exec-multiple-selections` - Execute all selected requests
- `:http-exec-buffer` - Execute all requests in buffer
- `:http-set-timeout [seconds]` - Set/show execution timeout (default: `30`)
- `:http-set-orientation [vsplit|hsplit]` - Set/show split direction (default: `vsplit`)
- `:http-toggle-headers` - Toggle response header inclusion (default: `true`)

### init.scm

A minimal `init.scm` enabling this plugin, with key bindings, might look something like the below:

```scheme
(require "cogs/keymaps.scm")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/configuration.scm")

(require "http-client.scm")

(keymap (global)
        (normal (space (H (c ":http-exec-selection")
                          (m ":http-exec-multiple-selections")
                          (b ":http-exec-buffer"))))
        (select (space (H (c ":http-exec-selection")
                          (m ":http-exec-multiple-selections")
                          (b ":http-exec-buffer")))))
```

### Test Files

See `test/` directory for example `.http` files demonstrating various features.

## LLM disclosure

I used Claude Code a bit to spin this up. It’s absolutely bloody terrible at Scheme, but be aware that not all of this code was written by humans, although one did read it.

## License

AGPL-3.0-or-later

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
