# Loads both modules fresh for every test file, the web module needs the core one.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../TabulaRasa') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..') -Force
