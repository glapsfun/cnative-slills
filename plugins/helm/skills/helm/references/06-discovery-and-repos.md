# Discovering and vendoring charts

Before authoring a chart from scratch, check whether a well-maintained one already exists — most common software (databases, ingress controllers, monitoring) has a mature community chart.

## Search

```bash
helm search hub <keyword>                 # search Artifact Hub (all public charts)
helm search hub wordpress --max-col-width 0
helm search repo <keyword>                # search repos you've already added locally
```

`helm search hub` queries [Artifact Hub](https://artifacthub.io), the central index of public Helm charts. It returns chart names, versions, and the repo URL to add. `helm search repo` only searches repositories already added to your local config.

## Add and update repositories (classic HTTP repos)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update                          # refresh cached index.yaml for all repos
helm repo list
helm repo remove bitnami
```

Always `helm repo update` before installing/searching so you see current versions. Repo metadata is cached locally as `index.yaml`.

## Inspect a chart before using it

Look before you install — understand the chart's values and contents:

```bash
helm show chart bitnami/postgresql        # Chart.yaml metadata
helm show values bitnami/postgresql       # default values.yaml (the config surface)
helm show readme bitnami/postgresql       # README
helm show all bitnami/postgresql          # everything
helm show values bitnami/postgresql --version 15.5.0   # pin to a version
```

`helm show values` is the fastest way to learn what you can configure. Pipe it to a file as a starting point for your overrides:

```bash
helm show values bitnami/postgresql > my-values.yaml
```

## Pull / vendor a chart locally

```bash
helm pull bitnami/postgresql --version 15.5.0            # download the .tgz
helm pull bitnami/postgresql --version 15.5.0 --untar    # download and unpack to ./postgresql
helm pull oci://registry-1.docker.io/bitnamicharts/postgresql --version 15.5.0 --untar
```

`helm pull` fetches a chart without installing it — for inspecting source, vendoring into a monorepo, or using as a dependency. `--untar` unpacks it.

## OCI registries

OCI registries (Helm 3.8+) are now first-class and increasingly the default distribution method. No `helm repo add` is needed — reference the `oci://` URL directly:

```bash
helm registry login registry-1.docker.io
helm show values oci://registry-1.docker.io/bitnamicharts/postgresql --version 15.5.0
helm install pg oci://registry-1.docker.io/bitnamicharts/postgresql --version 15.5.0
helm pull oci://registry-1.docker.io/bitnamicharts/postgresql --version 15.5.0
```

`helm search hub` does not index all OCI registries, so for OCI charts you typically know the registry path (from the project's docs) rather than discovering via search.

## Using an existing chart as a dependency

To build on a published chart, declare it in your `Chart.yaml` `dependencies` (HTTP or `oci://` repository), then:

```bash
helm dependency update ./mychart          # vendors it into charts/ and writes Chart.lock
```

Override its values by nesting under the dependency's name (or `alias`) in your `values.yaml`. See `references/01-chart-anatomy-and-authoring.md`.

## Choosing a chart: what to check

- **Maintenance & provenance:** recent releases, a reputable publisher, signed/verified on Artifact Hub.
- **Configurability:** does `helm show values` expose what you need (resources, securityContext, ingress, persistence)?
- **Kubernetes compatibility:** `Chart.yaml` `kubeVersion` vs your cluster.
- **Footprint:** does it pull in subcharts (e.g. a bundled database) you'd rather manage separately? Check `helm show chart` dependencies and disable with `condition` flags if so.
