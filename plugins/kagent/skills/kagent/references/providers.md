# LLM Provider Configuration

## Contents

- Supported providers
- CLI install (env vars)
- Helm install per provider
- ModelConfig CRD and provider-specific tuning fields
- TLS to provider endpoints
- API key passthrough
- Multiple providers
- BYO OpenAI-compatible provider
- xAI/Grok and SAP AI Core notes

kagent supports multiple LLM providers. Configure them via Helm values, the dashboard, or ModelConfig CRDs.

## Supported Providers

| Provider | Helm key | API key env var |
|----------|----------|-----------------|
| OpenAI | `openAI` | `OPENAI_API_KEY` |
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` |
| Azure OpenAI | `azureOpenAI` | `AZURE_OPENAI_API_KEY` |
| Google Gemini | `gemini` | `GOOGLE_API_KEY` |
| Google Vertex AI (Gemini) | `geminiVertexAI` | (service account — `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`) |
| Anthropic via Vertex AI | `anthropicVertexAI` | (service account — `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`) |
| Amazon Bedrock | `bedrock` | (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) |
| Ollama | `ollama` | (none — local, uses `OLLAMA_API_BASE` for endpoint) |
| xAI/Grok | OpenAI-compatible | `XAI_API_KEY` |
| SAP AI Core | `sapAICore` | OAuth2 client credentials in Secret |
| BYO OpenAI-compatible | custom | varies |

**Helm key convention:** Provider names are camelCase with lowercase first letter (e.g., `openAI`, `azureOpenAI`, `geminiVertexAI`). The `provider` field in ModelConfig uses PascalCase (`OpenAI`, `Anthropic`, `AzureOpenAI`, ...).

## CLI Install

The CLI uses `KAGENT_DEFAULT_MODEL_PROVIDER` to select the provider (defaults to `openAI` if not set). Set both the provider and API key:

```bash
export KAGENT_DEFAULT_MODEL_PROVIDER=openAI   # or anthropic, azureOpenAI, gemini, ollama
export OPENAI_API_KEY="sk-..."
kagent install --profile demo
```

For Anthropic:
```bash
export KAGENT_DEFAULT_MODEL_PROVIDER=anthropic
export ANTHROPIC_API_KEY="sk-ant-..."
kagent install --profile demo
```

## Helm Install (explicit)

### OpenAI
```bash
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=openAI \
  --set providers.openAI.apiKey=$OPENAI_API_KEY
```

### Anthropic
```bash
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=anthropic \
  --set providers.anthropic.apiKey=$ANTHROPIC_API_KEY
```

### Azure OpenAI
```bash
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=azureOpenAI \
  --set providers.azureOpenAI.apiKey=$AZURE_OPENAI_API_KEY
```

### Google Gemini
```bash
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=gemini \
  --set providers.gemini.apiKey=$GOOGLE_API_KEY
```

### Ollama (local models)
```bash
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=ollama
```

Ollama must be accessible from within the cluster (for Kind/minikube, that usually means the host's address as seen from pods, e.g. `host.docker.internal` or the docker bridge IP — not `localhost`).

## ModelConfig CRD

For fine-grained control, create ModelConfig resources directly:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: my-model-config
  namespace: kagent
spec:
  provider: OpenAI
  model: gpt-4.1
  apiKeySecret: my-api-key-secret     # name of K8s Secret
  apiKeySecretKey: api-key             # key within the Secret
```

Then reference it in your Agent:
```yaml
spec:
  declarative:
    modelConfig: my-model-config
```

### Provider-specific tuning fields

Each provider has an optional config block — it must only be set when `provider` matches (CEL-validated). Verify exact fields with `kubectl explain modelconfig.spec.<block>`:

| Block | Notable fields |
|---|---|
| `openAI` | `baseUrl`, `temperature`, `maxTokens`, `topP`, `frequencyPenalty`, `presencePenalty`, `seed`, `timeout`, `reasoningEffort` (minimal/low/medium/high) |
| `anthropic` | `baseUrl`, `maxTokens`, `temperature`, `topP`, `topK` |
| `azureOpenAI` | `azureEndpoint`, `apiVersion`, `azureDeployment` |
| `ollama` | `host`, `options` |
| `geminiVertexAI` / `anthropicVertexAI` | `projectID`, `location`, `temperature`, max token fields |
| `bedrock` | `region` |
| `sapAICore` | `baseUrl`, `authUrl`, `resourceGroup` |

Example with tuning:

```yaml
spec:
  provider: Anthropic
  model: claude-sonnet-4-5
  apiKeySecret: anthropic-key
  apiKeySecretKey: api-key
  anthropic:
    maxTokens: 8192
    temperature: 0.2
```

## TLS to Provider Endpoints

For self-hosted providers with custom CAs (vLLM behind an internal LB, corporate proxy):

```yaml
spec:
  tls:
    # caCertSecretRef + caCertSecretKey must be set together
    caCertSecretRef: internal-ca
    caCertSecretKey: ca.crt
    # disableVerify: true       # last resort — skips verification entirely
    # disableSystemCAs: false   # only trust the provided CA
```

## API Key Passthrough

`apiKeyPassthrough: true` makes the agent use the Bearer token from the *incoming* A2A request instead of a stored Secret — useful when callers bring their own LLM credentials. It is mutually exclusive with `apiKeySecret` and not allowed for Gemini/Vertex providers.

## Multiple Providers

You can configure multiple providers simultaneously. Create separate ModelConfig resources for each and reference the appropriate one per agent. This also covers mixed setups like a cheap model for routine agents and a stronger one for complex agents — or a separate embedding ModelConfig for memory (see `hitl-and-memory.md`).

## BYO OpenAI-Compatible Provider

For self-hosted or third-party OpenAI-compatible APIs (vLLM, Together, etc.), configure as OpenAI with a custom base URL:

```yaml
spec:
  provider: OpenAI
  model: my-model
  apiKeySecret: my-key
  apiKeySecretKey: api-key
  openAI:
    baseUrl: https://vllm.internal.example.com/v1
```

### xAI / Grok

xAI is configured as an OpenAI-compatible provider: create a Secret with `XAI_API_KEY`, set `provider: OpenAI`, and point the OpenAI-compatible base URL at `https://api.x.ai/v1`. Current docs differ between `baseUrl` and `baseURL` examples, so verify the exact field casing with `kubectl explain modelconfig.spec.openAI` for the installed CRD before applying YAML.

### SAP AI Core

SAP AI Core uses `provider: SAPAICore` and a `sapAICore` block. Its Secret stores OAuth2 `client_id` and `client_secret` values, and `apiKeySecretKey` is not used. Required provider settings include the SAP AI Core base URL and model name; `authUrl` and `resourceGroup` are commonly set from the service key.
