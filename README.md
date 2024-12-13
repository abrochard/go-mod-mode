# go-mod-mode

Major mode for golang `go.mod` and `go.sum` files.

## Installation

``` emacs-lisp
(package-vc-install "https://github.com/abrochard/go-mod-mode")
(require 'go-mod-mode)
(flycheck-go-mod-setup)
```

## Usage

`C-c C-o` to open the menu when visiting a `go.mod` file:


```
t -> go mod tidy
u -> upgrade a package
U -> upgrade all packages
i -> import a package
g -> get version
r -> replace a package with local version
w -> go mod why
```

Note: actions targetting a specific package will target the one
under the cursor, or else make you select one from a pop up.
