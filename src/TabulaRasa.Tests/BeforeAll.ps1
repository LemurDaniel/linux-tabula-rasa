# Loads the module fresh for every test file, it lives next to this folder.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../TabulaRasa') -Force
