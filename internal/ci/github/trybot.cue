// Copyright 2022 The CUE Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package github

import (
	"list"
	"strings"
	"strconv"
	encjson "encoding/json"

	"github.com/SchemaStore/schemastore/src/schemas/json"

	"github.com/cue-lang/cuelang.org/internal/ci/netlify"
)

workflows: trybot: _repo.bashWorkflow & {
	on: {
		push: {
			branches: list.Concat([[_repo.testDefaultBranch], _repo.protectedBranchPatterns]) // do not run PR branches
			"tags-ignore": [_repo.releaseTagPattern]
		}
	}

	jobs: test: {
		strategy: {
			"fail-fast": false
			matrix: {
				"go-version": [_repo.latestStableGo]

				// Always run on Linux. Run on macOS (very slow runners) for
				// commits in the target branch in the main repo. Everywhere else
				// (CLs, PRs, trybot repo) do not run macOS.
				//
				// The uses the little-documented ternary operator... which isn't
				// the prettiest of things.
				runner: """
				${{
					((! \(_repo.containsDispatchTrailer)) && (github.repository == '\(_repo.githubRepositoryPath)')) &&
					fromJSON('\(encjson.Marshal([_repo.linuxMachine, _repo.macosMachine]))') ||
					fromJSON('\(encjson.Marshal([_repo.linuxMachine]))')
				}}
				"""
			}
		}
		"runs-on": "${{ matrix.runner }}"

		steps: [
			_updateHomebrew,

			for v in _repo.checkoutCode {v},

			_repo.earlyChecks,

			for v in _installDockerMacOS {v},

			_installMacOSUtils,
			_setupBuildx,
			_installNode,
			_installGo,
			_installHugoLinux,
			_installHugoMacOS,

			// cachePre must come after installing Node and Go, because the cache locations
			// are established by running each tool.
			for v in _setupGoActionsCaches {v},

			// Disable checkout for "latest" CUE for now. Go does not (yet)
			// handle a query for cuelang.org/go@v0.6 when there is only a
			// prerelease version matching that query.
			//
			// json.#step & {
			// 	// The latest git clean check ensures that this call is effectively
			// 	// side effect-free. Using GOPRIVATE ensures we don't accidentally
			// 	// hit a stale cache in the proxy.
			// 	name: "Ensure latest CUE"
			// 	run: """
			// 		GOPRIVATE=cuelang.org/go go get -d cuelang.org/go@latest
			// 		go mod tidy
			// 		go mod tidy
			// 		"""
			// },

			// Rebuild docker image
			json.#step & {
				run: "./_scripts/buildDockerImage.bash"
			},

			// Go generate steps
			_goGenerate & {
				name: "Regenerate"
			},

			// npm install in hugo to allow serve test to pass
			//
			// TODO: make this a more principled change.
			json.#step & {
				run:                 "npm install"
				"working-directory": "hugo"
			},

			// Go test steps
			_goTest & {
				name: "Test"
			},

			// Run staticcheck
			json.#step & {
				name: "staticcheck"
				run:  "./_scripts/staticcheck.bash"
			},

			// go mod tidy
			_modTidy & {
				name: "Check module is tidy"
			},

			_dist,
			_repo.checkGitClean,

			// Now the frontend build has happened, ensure that linters pass
			json.#step & {
				"working-directory": "hugo"
				run: """
					npm run lint
					"""
			},

			// Only run a deploy of tip if we are running as part of the trybot repo,
			// with a TryBot-Trailer, i.e. as part of CI check of the trybot workflow
			_netlifyDeploy & {
				if:     "github.repository == '\(_repo.trybotRepositoryPath)' && \(_repo.containsTrybotTrailer) && \(_isLatestLinux)"
				#site:  _repo.netlifySites.cls
				#alias: "cl-${{ \(_dispatchTrailerExpr).CL }}-${{ \(_dispatchTrailerExpr).patchset }}"
				name:   "Deploy preview of CL"
			},

			json.#step & {
				// Only run in the main repo on the alpha branch. Because anywhere else
				// doesn't make sense.
				if:                  "github.repository == '\(_repo.githubRepositoryPath)' && (github.ref == 'refs/heads/\(_repo.alphaBranch)') && \(_isLatestLinux)"
				run:                 "npm run algolia"
				"working-directory": "hugo"
				env: {
					ALGOLIA_APP_ID:     "5LXFM0O81Q"
					ALGOLIA_ADMIN_KEY:  "${{ secrets.ALGOLIA_INDEX_KEY }}"
					ALGOLIA_INDEX_NAME: "cuelang.org"
					ALGOLIA_INDEX_FILE: "../_public/algolia.json"
				}
			},
		]
	}

	let matrixRunner = "matrix.runner"
	let goVersion = "matrix.go-version"

	// _isLatestLinux returns a GitHub expression that evaluates to true if the job
	// is running on Linux with the latest version of Go. This expression is often
	// used to run certain steps just once per CI workflow, to avoid duplicated
	// work.
	_isLatestLinux: "(\(goVersion) == '\(_repo.latestStableGo)' && \(matrixRunner) == '\(_repo.linuxMachine)')"

	// TODO: this belongs in base. Captured in cuelang.org/issue/2327
	_dispatchTrailerExpr: "fromJSON(steps.DispatchTrailer.outputs.value)"
	_goGenerate:          json.#step & {
		name: string
		run:  "go generate ./..."
	}

	_goTest: json.#step & {
		name: string
		run:  "go test ./..."
	}

	_modTidy: json.#step & {
		name: string
		run:  "go mod tidy"
	}
}

_installNode: json.#step & {
	name: "Install Node"
	uses: "actions/setup-node@v3"
	with: {
		"node-version": _repo.nodeVersion
	}
}

_installGo: _repo.installGo & {
	with: "go-version": _repo.goVersion
}

_installHugoLinux: _linuxStep & {
	name: "Install Hugo (${{ runner.os }})"
	uses: "peaceiris/actions-hugo@v2"
	with: {
		"hugo-version": _repo.hugoVersion
		extended:       true
	}
}

_installHugoMacOS: _macOSStep & {
	name: "Install Hugo (${{ runner.os }})"
	run:  "brew install hugo"
}

_installDockerMacOS: [
			..._macOSStep & {
		_name: string
		name:  _name + " (${{runner.os}})"
	},
] & [
	// Set TMPDIR to be within the HOME directory so that bind mounts with
	// docker (via colima) work. If we don't set this to be a path within $HOME,
	// then we end up with a mount-ed directory. And this does not work via -v
	// bind mounts.
	json.#step & {
		_name: "Set TMPDIR environment variable"
		run: """
			mkdir $HOME/.tmp
			echo "TMPDIR=$HOME/.tmp" >> $GITHUB_ENV
			"""
	},
	json.#step & {
		_name: "Write lima config"
		run: """
			mkdir -p ~/.lima/default
			cat <<EOD > ~/.lima/default/lima.yaml
			mounts:
			  - location: "~"
				 writable: true
			  - location: "$TMPDIR"
				 writable: true
			EOD
			"""
	},
	json.#step & {
		_name: "Install Docker"
		run: """
			brew install colima docker
			colima start --mount-type virtiofs
			sudo ln -sf $HOME/.colima/default/docker.sock /var/run/docker.sock
			"""
	},
	json.#step & {
		_name: "Set DOCKER_HOST environment variable"
		run: """
			echo "DOCKER_HOST=unix://$HOME/.colima/default/docker.sock" >> $GITHUB_ENV
			"""
	},
]

_macOSStep: json.#step & {
	if: "runner.os == 'macOS'"
}

_linuxStep: json.#step & {
	if: "runner.os == 'Linux'"
}

_updateHomebrew: _macOSStep & {
	name: "Update Homebrew (macOS)"
	run: """
		brew update
		"""
}

_installMacOSUtils: _macOSStep & {
	name: "Install macOS utils"
	run: """
		brew install coreutils
		"""
}

_dist: json.#step & {
	name: *"Dist" | string
	run:  "./_scripts/build.bash"
}

_tipDist: _dist & {
	name: "Tip dist"
	env: BRANCH: "tip"
}

_installNetlifyCLI: json.#step & {
	name: "Install Netlify CLI"
	run:  "npm install -g netlify-cli@\(_repo.netlifyCLIVersion)"
}

// _netlifyDeploy is used to push CLs for preview but also to deploy tip
_netlifyDeploy: json.#step & {
	#prod:   *false | bool
	#site:   string
	#alias?: string
	if !#prod {
		#alias: *"" | string
	}
	let nc = netlify.config
	let prod = [ if #prod {"--prod"}, ""][0]
	let uSite = strings.ToUpper(strings.Replace(#site, "-", "_", -1))
	let alias = [ if #alias != _|_ if #alias != "" {"--alias \(#alias)"}, ""][0]

	name: string
	run:  "netlify deploy \(alias) -f \(nc.build.functions) -d \(nc.build.publish) -m \(strconv.Quote(name)) -s \(#site) --debug \(prod)"
	env: NETLIFY_AUTH_TOKEN: "${{ secrets.NETLIFY_AUTH_TOKEN_\(uSite)}}"
}

// _setupGoActionsCaches is shared between trybot and update_tip.
_setupGoActionsCaches: _repo.setupGoActionsCaches & {
	#goVersion: _installGo.with."go-version"

	// Unfortunate that we need to hardcode here. Ideally we would be able to derive
	// the OS from the runner. i.e. from _linuxWorkflow somehow.
	#os: "${{ runner.os }}"

	#additionalCacheDirs: [
		"~/.cache/dockercache",
		"${{ github.workspace }}/playground/.webpack_cache",
	]

	_
}

_setupBuildx: json.#step & {
	name: "Set up Docker Buildx"
	uses: "docker/setup-buildx-action@v2"
}
