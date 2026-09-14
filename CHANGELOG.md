# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Accepts Spectral 0.14.x as well as 0.13.x, and is tested against the released Spectral 0.14.0 with spectra 0.14.1.
- `EctoSpectral.JSONB`, an `Ecto.ParameterizedType` that stores a Spectral-typed value in a `jsonb` column. Parameterized by `:module` and `:type`, with `:on_load_error` to choose what a load failure does.
- `EctoSpectral.LoadError`, raised when a stored document does not match the declared type. Carries the `Spectral.Error` list that `c:Ecto.ParameterizedType.load/3` cannot return.
