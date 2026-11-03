# Loads both modules fresh for every test file, the web module needs the core one. Both live next to this folder.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../TabulaRasa') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../TabulaRasa.Web') -Force
