# Indented.ChocoPackage

[![Build status](https://ci.appveyor.com/api/projects/status/tfbu1btn3wt4r77s?svg=true)](https://ci.appveyor.com/project/indented-automation/indented-chocopackage)

A PowerShell command which creates a chocolatey package from a PowerShell module.

Separate packages for individual dependencies are created.

## Installation

```powershell
Install-Module Indented.ChocoPackage
```

## Usage

Create a chocolatey package from an existing imported module

```powershell
Get-Module Indented.ChocoPackage | ConvertTo-ChocoPackage
```

Create a chocolatey package from a module on the local machine.

```powershell
Get-Module Indented.ChocoPackage -ListAvailable | ConvertTo-ChocoPackage
```

Create a chocolatey package from a module via Find-Module.

```powershell
Find-Module Indented.ChocoPackage | ConvertTo-ChocoPackage
```
