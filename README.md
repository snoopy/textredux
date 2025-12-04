Textredux is a module for the [Textadept editor](http://foicica.com/textadept/)
that offers a set of text based replacement interfaces for core Textadept
functionality.

This fork adds some fixes and features.

* Fix default and quick filters
* Fix Save-as functionality
* Rework file dialog keybinds
    * F7 to create a new folder
    * alt+r to jump to root (/)
    * alt+u to jump to userhome (~)

![](docs/images/bufferlist.gif)

Branches:
* master
    * stable mainline branch
* testing
    * somewhat stable for long-term feature tests
* dev
    * unstable for experimental changes
* upstream
    * original upstream branch

The API docs are generated with [ldoc](https://stevedonovan.github.io/ldoc/):

```
cd docs
ldoc .
```

The Textredux module is released under the MIT license.
Please visit the [homepage](http://rgieseke.github.com/textredux/) for
more information.
