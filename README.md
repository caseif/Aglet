# Aglet

Aglet is the *A*rgus *G*raphics *L*ibrary *E*xtension *T*ool. It is capable of generating customized loader code for
OpenGL functions for use with C/C++ programs.

## Setup

Aglet requires Ruby >=2.5 and the [Nokogiri](https://nokogiri.org) gem.

```
gem install nokogiri
```

## Usage

Aglet's CLI usage is as follows:

```
aglet.rb -p <profile> -o <output path>
```

| Short parameter | Long parameter | Description |
| :-: | :-: | :-- |
| `-p <profile>` | `--profile=<profile>` | A path to the profile configuration file, described below. |
| `-o <output path>` | `--output=<output path>` | The path to the directory to emit output files to. |

### Profile Configuration

Aglet requires a profile configuration in XML format in order to generate loader code. An example of this file is below.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<profile>
    <api>
        <!-- The API to generate a loader for. Accepted strings are 'gl', 'glcore', 'gles1', 'gles2', and 'glsc'. -->
        <!-- Note that this does not constitute a minimum version. Aglet will not verify whether your context meets -->
        <!-- a certain version requirement. -->
        <name>glcore</name>
        <!-- The version of the specified API to generate a loader for. Accepted values vary by API. -->
        <version>3.3</version>
    </api>
    <!-- A set of extensions to be loaded. The `required` attribute is optional and defaults to 'true'. -->
    <extensions>
        <extension required="false">GL_KHR_debug</extension>
    </extensions>
</profile>
```

Note that extensions marked as required per the profile config will cause the loader routine to fail if they are not
available. Non-required extensions will be ignored if not available.

## Planned Features

- Multi-version configuration to allow loading of optional features
- Per-context function loading
