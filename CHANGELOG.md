# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Depends on unreleased git branches of Spectral (`andreashasse/pre-encoded-nil`) and spectra (`andreashasse/nil-fields-per-call`) so they can be tested together before the 0.17 releases. To be reverted to hex versions once those are out.
- Updated `decimal` to 3.2.0 in the lock file.

### Added
- Postgres regression test: with `config :spectra, :nil_fields, :null`, a nil field is stored as JSON `null` in the `jsonb` column, not the string `"null"`, and loads back as `nil`.

## [0.1.0] - 2026-09-14

### Added
- Requires Spectral 0.14 and spectra 0.14.1, the first spectra release that returns an error rather than crashing when a struct type is encoded with a value that is not a map.
- `EctoSpectral.JSONB`, an `Ecto.ParameterizedType` that stores a Spectral-typed value in a `jsonb` column. Parameterized by `:module` and `:type`, with `:on_load_error` to choose what a load failure does.
- `EctoSpectral.LoadError`, raised when a stored document does not match the declared type. Carries the `Spectral.Error` list that `c:Ecto.ParameterizedType.load/3` cannot return.
