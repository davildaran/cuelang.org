---
title: Working with a custom module registry
authors:
- rogpeppe
tags:
- modules
- tooling
- cue command
toc_hide: true
---

## Introduction

In this tutorial you will learn how to create and work with CUE modules,
using a custom module registry.

Along the way you will:

- Define a module containing a CUE schema
- Push the module to a custom registry
- Define a top level module that depends on the first module
- Use `cue mod tidy` to automatically add dependencies and their versions to the `module.cue` file
- Publish a module containing a CUE template that depends on the schema
- Update the top level module to depend on the template
- Update the schema and its version, and update the top level module to depend on the new version

{{< info >}}
This tutorial describes an experimental feature. All details are subject to change.
{{< /info >}}

## Prerequisites

- **A tool to edit text files**. Any text editor you have will be fine, for
  example [VSCode](https://code.visualstudio.com/).
- **A command terminal**. `cue` works on all platforms, so any terminal on Linux
  or macOS, and on PowerShell, `cmd.exe` or
  [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) in Windows.
- **The docker command** or an Open Container Initiative ("OCI") registry that
  you can write to.
- **An installed `cue` binary**
  ([installation details]({{< relref "/docs/introduction/installation" >}}))
- **Some awareness of CUE schemata**
  ([Constraints]({{< relref "/docs/tour/basics/constraints" >}}) and
   [Definitions]({{< relref "/docs/tour/basics/definitions" >}}) in the CUE tour)

## Create the module for the schema code

In this tutorial we will focus on an imaginary application called `FrostyApp`,
which consumes its configuration in YAML format.
You will define the configuration in CUE and use a CUE schema to validate it.
We would like to be able to share the schema between several consumers.

{{{with step}}}

Create a directory to hold the schema code:
{{{with script "en" "create-frostyconfig"}}}
#norun

mkdir frostyconfig
cd frostyconfig
{{{end}}}

Each module described in this tutorial will live in a separate directory, which
you will create as they are needed.
{{{end}}}

{{{with step}}}

Initialize the directory as a module:
{{{with script "en" "initialize-frostyconfig-module"}}}
#norun

cue mod init glacial-tech.example/frostyconfig@v0
{{{end}}}

In order to publish the module to a registry, the code must hold a
`cue.mod/module.cue` file declaring its module path. This is the path prefix to
use when importing packages from within the module.

Module paths are fully domain-name qualified,
and it is good practice to place the module under a domain
or a GitHub repository that you control.

We will use a custom registry in this tutorial,
which has fewer restrictions on the module paths that can be used.
By contrast a central shared registry may
require proof of control of a domain
before allowing updates to a module in that domain.

In our example we will assume that
we control the domain name `glacial-tech.example`
and place all module paths under that.

There are some other constraints on the names
that can be used for a module, due to OCI restrictions.
The module name must contain only
lower-case ASCII letters, ASCII digits, dots (`.`), and dashes (`-`).
The
[OCI distribution spec](https://github.com/opencontainers/distribution-spec/blob/main/spec.md#pulling-manifests)
contains full details of the naming restrictions.
{{{end}}}

{{< info >}}
Modules are always named with the major version at the end of the module path.
This is independent from the naming restrictions detailed above: the same OCI
repository is used for all major and minor versions of a given module in a
registry.
{{< /info >}}

{{{with step}}}

Create the configuration schema:
{{{with upload "en" "schema-v0.0.1"}}}
-- frostyconfig/config.cue --
package frostyconfig

// #Config defines the schema for the FrostyApp configuration.
#Config: {
	// appName defines the name of the application.
	appName!: string
	// port holds the port number the application listens on.
	port!: int
	// debug holds whether to enable debug mode.
	debug?: bool
	// features holds optional feature settings
	features?: {
		// logging enables or disables logging.
		logging?: bool
		// analytics enables or disables analytics.
		analytics?: bool
	}
}
{{{end}}}

The details of the schema are not too important. For the purposes of this tutorial,
it represents the schema of the configuration data expected by `FrostyApp`.

{{{end}}}

## Choose an OCI registry

{{{with step}}}

If you do not have access to an OCI registry, start one locally:
{{{with script "en" "start-registry"}}}
#norun

docker run -p 5000:5000 registry
{{{end}}}

CUE should work with all OCI-compatible artifact registries, such as
the [Google Artifact Registry](https://cloud.google.com/artifact-registry),
as CUE uses the standard OCI protocols spoken by such registries.

In our example we will run a local instance of the docker registry on port 5000.
If you need to run one locally, invoke the above `docker` command in a separate
terminal so the registry remains running while you follow the rest of this
tutorial.
{{{end}}}

## Publish the module

{{{with step}}}

Set up some required envirionment variables:
{{{with script "en" "init-environ"}}}
#norun

export CUE_EXPERIMENT=modules
export CUE_REGISTRY=localhost:5000/cuemodules
{{{end}}}

The `CUE_EXPERIMENT` variable is necessary because the modules registry
support is currently in its experimental phase.

The `CUE_REGISTRY` variable tells the `cue` command which
registry to use when fetching and pushing modules.
In our example the modules will be stored in the registry under the prefix `cuemodules`.
In practice you would want this prefix to be some place of your choice - 
or you could leave the prefix empty if you plan to dedicate the registry
to holding CUE modules.
{{{end}}}

{{{with step}}}

Ensure the `module.cue` file is tidy:
{{{with script "en" "frostyconfig-v0.0.1-tidy"}}}
#norun

cue mod tidy
{{{end}}}
This command checks that modules for all imported packages
are present in the `cue.mod/module.cue` file and that their versions
are correct. It is good practice to run this before publishing
a module. So, although this module does not
have any dependencies, we will run `cue mod tidy` anyway.
{{{end}}}

{{{with step}}}

Publish the first version of this module:
{{{with script "en" "frostyconfig-v0.0.1-publish"}}}
#norun

cue mod publish v0.0.1
{{{end}}}

This command uploads the module to the registry and publishes it
under version `v0.0.1`. It will be published to the module
path we chose in `cue mod init` earlier - all we need to do in this command
is to decide which version we will publish.
The version follows [semver syntax](https://semver.org),
and it is good practice to follow semantic version *conventions*, which include
maintaining compatability with earlier minor versions of the same module.

The major version under which it is published
**must** match the major version specified in the module file.
For example it would be an error to use `v1.0.1` here
because the module name ends in `@v0`.

The module has now been published to the registry. If you are running a
registry locally then you might have seen some output in the `docker` terminal
while the registry received and stored the module.
{{{end}}}

## Create a new `frostyapp` module that depends on the first module

Define the actual `FrostyApp` configuration, constrained by the schema you just
published.

{{{with step}}}

Create a directory for the new module and initalize it:
{{{with script "en" "init-frostyapp"}}}
#norun

mkdir ../frostyapp
cd    ../frostyapp
cue mod init glacial-tech.example/frostyapp@v0
{{{end}}}
{{{end}}}

{{{with step}}}

Create the code for the new module:
{{{with upload "en" "config.cue"}}}
-- frostyapp/config.cue --
package frostyapp

import "glacial-tech.example/frostyconfig@v0"

config: frostyconfig.#Config & {
	appName: "alpha"
	port:    80
	features: logging: true
}
{{{end}}}

This imports the `frostyconfig` package from the first
module you published and
defines some concrete values for the configuration,
constrained by the `frostyconfig.#Config` schema.
{{{end}}}

{{{with step}}}

Ensure the module is tidy, pulling all dependencies:
{{{with script "en" "frostyapp-tidy-1"}}}
#norun

cue mod tidy
{{{end}}}

We can see that the dependencies have now been added to the
`cue.mod/module.cue` file:

<!-- TODO: show actual file content -->
{{{with upload "en" "frostyapp-tidy-result-1"}}}
-- frostyapp/cue.mod/module.cue --
module: "glacial-tech.example/frostyapp@v0"
deps: {
	"glacial-tech.example/frostyconfig@v0": {
		v: "v0.0.1"
	}
}
{{{end}}}

Our dependencies currently look like this:
{{< mermaid caption="Current dependencies" >}}
flowchart TD
    frostyapp--  v0.0.1 --> frostyconfig
{{< /mermaid >}}
{{{end}}}

## Evaluate the configuration

{{{with step}}}

Export the configuration as YAML:
{{{with script "en" "frostyapp-export-1"}}}
#norun

cue export --out yaml
{{{end}}}

We can use this new module code just like any other CUE code.

<!-- TODO: show actual file content -->
Here is the output:
```
config:
  appName: alpha
  port: 80
  features:
    logging: true
```
{{{end}}}

## Publish a `frostytemplate` module

Suppose we want to define a module that encapsulates some
default values for `FrostyApp`. We _could_ just publish it as part of the
`frostyconfig` original module, but publishing it as a separate module will
be useful to demonstrate how dependencies work. Having different modules like
this can also be a useful separation of concerns when a schema comes from some
other source of truth.

{{{with step}}}

Create a directory for the new module and initalize it:
{{{with script "en" "init-frostytemplate"}}}
#norun

mkdir ../frostytemplate
cd    ../frostytemplate
cue mod init glacial-tech.example/frostytemplate@v0
{{{end}}}

This defines another module. We have named it `frostytemplate`
because CUE uses the term "template" to mean code that
defines default values and derived data but is not intended to
be the final configuration.
{{{end}}}

{{{with step}}}

Define the CUE template:
{{{with upload "en" "second-module-to-publish"}}}
-- frostytemplate/template.cue --
package frostytemplate

import "glacial-tech.example/frostyconfig@v0"

// Config defines a set of default values for frostyconfig.#Config.
Config: frostyconfig.#Config & {
	port:  *80 | _
	debug: *false | _
	features: {
		logging:   *true | _
		analytics: *true | _
	}
}
{{{end}}}

We import the schema to constrain the default values, just as we did with the
`frostyapp` module.
{{{end}}}

{{{with step}}}

Publish the `frostytemplate` module:
{{{with script "en" "frostytemplate-v0.0.1-publish"}}}
#norun

cue mod tidy
cue mod publish v0.0.1
{{{end}}}
{{{end}}}

## Update the `frostyapp` module

{{{with step}}}

Update the `frostyapp` module to make use of this new template
module:
{{{with upload "en" "update-frostyapp"}}}
-- frostyapp/config.cue --
package frostyapp

import "glacial-tech.example/frostytemplate@v0"

config: frostytemplate.Config & {
	appName: "alpha"
}
{{{end}}}

The `frostyapp` module now gains the benefit of the new defaults. We can remove
some fields because they are now provided by the template, satisfying the
requirements of the configuration.
{{{end}}}

{{{with step}}}

Resolve dependencies in `frostyapp`:
{{{with script "en" "frostyapp-tidy-2"}}}
#norun

cue mod tidy
{{{end}}}

Re-running `cue mod tidy` updates the dependencies in `frostyapp` to
use `frostytemplate` as well as `frostyconfig`.

Here is what the `cue.mod/module.cue` file now looks like:

<!-- TODO: show actual file content -->
{{{with upload "en" "frostyapp-tidy-result-2"}}}
-- frostyapp/cue.mod/module.cue --
module: "glacial-tech.example/frostyapp@v0"
deps: {
	"glacial-tech.example/frostyconfig@v0": {
		v: "v0.0.1"
	}
	"glacial-tech.example/frostytemplate@v0": {
		v: "v0.0.1"
	}
}
{{{end}}}

{{< mermaid caption="Current dependencies" >}}
flowchart TD
    frostyapp--  v0.0.1 --> frostytemplate
    frostytemplate--  v0.0.1 --> frostyconfig
{{< /mermaid >}}
{{{end}}}

{{{with step}}}

Re-render the configuration as YAML:
{{{with script "en" "rerender-config"}}}
#norun

cue export --out yaml
{{{end}}}

We can see that the values in the configuration reflect the new default values:

<!-- TODO: show actual file content -->
```
config:
  appName: alpha
  port: 80
  debug: false
  features:
    logging: true
    analytics: true
```
{{{end}}}

## Add a new field to the schema

Suppose that `FrostyApp` has gained the ability to limit the amount of
concurrency it uses, configured with a new `maxConcurrency` field.
We will add that field to the schema and update the app to use it.

{{{with step}}}

Update the schema to add a new `maxConcurrency` field:
{{{with upload "en" "schema-v0.1.0"}}}
-- frostyconfig/config.cue --
package frostyconfig

// #Config defines the schema for the FrostyApp configuration.
#Config: {
	// appName defines the name of the application.
	appName!: string
	// port holds the port number the application listens on.
	port!: int
	// debug holds whether to enable debug mode.
	debug?: bool
	// maxConcurrency specifies the maximum amount of
	// concurrent requests to process concurrently.
	maxConcurrency?: int & >=1
	// features holds optional feature settings
	features?: {
		// logging enables or disables logging.
		logging?: bool
		// analytics enables or disables analytics.
		analytics?: bool
	}
}
{{{end}}}

The schema is unchanged except for the new `maxConcurrency` field.
{{{end}}}

{{{with step}}}

Upload a new version of the `frostyconfig` schema:
{{{with script "en" "upload-schema2"}}}
#norun

cd ../frostyconfig
cue mod tidy
cue mod publish v0.1.0
{{{end}}}

We incremented the minor version to signify that a backwardly
compatible feature has been added.
{{{end}}}

## Update the `frostyapp` module to use the new schema version

{{{with step}}}

Edit the `cue.mod/module.cue` file to use the new version:
{{{with upload "en" "edit-dependency-version"}}}
-- frostyapp/cue.mod/module.cue --
module: "glacial-tech.example/frostyapp@v0"
deps: {
	"glacial-tech.example/frostyconfig@v0": {
		v: "v0.1.0" // Note: this changed from before.
	}
	"glacial-tech.example/frostytemplate@v0": {
		v: "v0.0.1"
	}
}
{{{end}}}

CUE modules "lock in" the versions of any dependencies, storing
their versions in `cue.mod/module.cue` file. This gives predictability
and dependability but does mean that our `frostyapp` application
will not use the new schema version until it is explicitly updated to do so.

{{< mermaid caption="Current dependencies" >}}
flowchart TD
    frostyapp--  v0.0.1 --> frostytemplate
    frostyapp--  v0.1.0 --> frostyconfig
    frostytemplate--  v0.0.1 --> frostyconfig
{{< /mermaid >}}
{{{end}}}

{{< info >}}
Here, you updated the version in the `module.cue` file manually, but in the
future the `cue` command will be able to perform this kind of update.
{{< /info >}}

{{{with step}}}

Check that everything still works and that your configuration is still valid:
{{{with script "en" "check-update-ok"}}}
#norun

cue mod tidy
cue export --out yaml
{{{end}}}

So exactly has happened above?

Recall that the `glacial-tech.example/frostytemplate` module remains unchanged:
its module still depends on the original `v0.0.1` version of the schema. By
changing the version at the top level (`frostyapp`), you caused the new version
to be used.

In general, we will end up with the the most recent version of all the major
versions mentioned in all dependencies. Put another way, there can be several
different major versions of a given module, but only one minor version. This is
the [MVS algorithm](https://research.swtch.com/vgo-mvs) used by CUE's
dependency resolution.
{{{end}}}

## Related content