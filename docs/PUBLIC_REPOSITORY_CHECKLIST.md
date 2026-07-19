# Public Repository Checklist

## Decisions

- The repository will be public to make source and development history viewable and to use standard GitHub-hosted runners under the public-repository policy.
- This is not an open-source release. Original project materials remain All Rights Reserved unless a file explicitly states otherwise.
- Existing commit history, pull requests, Actions logs, `HANDOFF.md`, `AGENTS.md`, `input/`, and `docs/CODEX_*` are intentionally retained and will become public.
- No history rewrite is planned because no committed private key, certificate, provisioning profile, API key value, or signing password was found in the reviewed files and signing-related commits.

## Before changing visibility

- [ ] Merge the public-repository preparation PR into `main`.
- [ ] Merge or close any other open PR whose contents should not become public.
- [ ] Review old TestFlight and signing-related Actions logs, or delete the runs if retaining them has no value.
- [ ] Confirm `input/icon.png` and `input/画面案.png` are owned by the repository owner and contain no personal information.
- [ ] Confirm repository Secrets contain only current credentials.
- [ ] Rotate any credential that may have been pasted into an issue, pull request, commit, or Actions log.

## Visibility change

Change repository visibility from Private to Public in GitHub repository settings only after the items above are complete.

## Immediately after changing visibility

- [ ] Confirm the repository is public from a signed-out browser session.
- [ ] Enable secret scanning and push protection where available.
- [ ] Recreate or verify the `main` branch ruleset because visibility changes can affect repository rules.
- [ ] Block force pushes and branch deletion on `main`.
- [ ] Require pull requests for `main` changes when practical.
- [ ] Confirm Actions workflow permissions remain read-only by default.
- [ ] Confirm only collaborators with write access can manually run the TestFlight workflow.
- [ ] Confirm repository Secrets are not visible in workflow logs.

## Ongoing rules

- Never commit `.p8`, `.p12`, private keys, certificates, provisioning profiles, Base64 exports, `.env` files, or production service configuration files.
- Never upload real school prints, OCR content, names, addresses, phone numbers, or calendar data to issues, pull requests, or Actions artifacts.
- Pin third-party Actions to immutable commit SHAs.
- Review dependency license and privacy terms before adding a library, model, or SDK.
