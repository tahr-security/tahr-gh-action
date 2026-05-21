# Tahr Github Action

Trigger a Tahr CI/CD assessment from a Github Actions workflow.

This action queues an assessment through the Tahr application CI/CD trigger endpoint and returns the queued assessment id. It does not wait for the scan to finish.

## Usage

```yaml
- name: Tahr Assessment Trigger
  uses: yack-security/tahr-gh-action@v1
```

```yaml
name: Deploy and scan

on:
  push:
    branches:
      - main

jobs:
  deploy-and-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Your app deployment
        run: ./deploy_my_app.sh

      - name: Trigger Tahr assessment
        id: tahr
        uses: yack-security/tahr-gh-action@v1
        with:
          application-id: ${{ vars.TAHR_APPLICATION_ID }}
          trigger-token: ${{ secrets.TAHR_TRIGGER_TOKEN }}
          assessment-type: source_code_analysis

      - name: Print assessment id
        run: echo "Queued Tahr assessment ${{ steps.tahr.outputs.assessment-id }}"
```

## Inputs

| Name              | Required | Default                | Description                                                                                        |
| ----------------- | -------- | ---------------------- | -------------------------------------------------------------------------------------------------- |
| `api-url`         | No       | `https://api.tahr.one` | Tahr API base URL.                                                                                 |
| `application-id`  | Yes      |                        | Tahr application id.                                                                               |
| `trigger-token`   | Yes      |                        | CI/CD trigger token generated in Tahr application settings. Store this as a Github Actions secret. |
| `assessment-type` | No       | `source_code_analysis` | Assessment type key enabled for CI/CD in Tahr.                                                     |
| `reserved-ip-id`  | No       |                        | Optional reserved scanner IP id.                                                                   |

## Allowed assessment types

These default keys can be used when they are published and allowed for CI/CD in Tahr:

- `full`
- `full-no-authz`
- `authorization_only`
- `api-test`
- `client-side`
- `recon`
- `source_code_analysis`

## Outputs

| Name              | Description                                       |
| ----------------- | ------------------------------------------------- |
| `assessment-id`   | Tahr assessment id queued by the trigger.         |
| `assessment-type` | Assessment type accepted by Tahr.                 |
| `status`          | Queue status returned by Tahr, normally `queued`. |

## Tahr setup

1. Open the target application in Tahr.
2. Open the CI/CD tab.
3. Generate a trigger token.
4. Add the token to Github as `TAHR_TRIGGER_TOKEN`.
5. Add `TAHR_APPLICATION_ID` as a repository or organization variable.
6. Make sure the selected assessment type is published and allowed for CI/CD in Tahr.

If an assessment type is not allowed for CI/CD, the action fails with `Unsupported assessment type`.

## Security notes

Do not expose the trigger token in workflows that run untrusted pull request code. Prefer running this action after deployment from protected branches.
