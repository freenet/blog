# Freenet Blog

A static [Hugo](https://gohugo.io) blog published on Freenet as a signed website contract.

Read it on any machine running Freenet:

http://127.0.0.1:7509/v1/contract/web/CaK7kGohya2cLhoXQTLgBsrjDVLZKszD6ktexjRSaXCf/

## Writing a post

Each post is a page bundle: `content/posts/<slug>/index.md`, with any charts or
other files next to it. Front matter needs `title`, `date` and a one-sentence
`description`.

Raw HTML is allowed in posts. For anything with a `<script>`, put it in its own
file in the bundle and include it with `{{< include "chart.html" >}}`, so
Markdown does not reformat it. Pages must be self-contained: no CDN scripts,
fonts or stylesheets, because a Freenet node may not be able to reach them.

House style: plain, literal sentences and no em-dashes. `scripts/check.sh`
fails on an em-dash.

## Building

```bash
hugo server            # local preview at http://localhost:1313/
scripts/check.sh       # the checks CI runs
```

All internal links are relative (`baseURL = "/"` with `relativeURLs = true`),
because the site is served under `/v1/contract/web/<key>/`. Do not use
root-relative links (`/posts/...`) in posts or templates.

## Publishing

```bash
scripts/publish.sh --preview   # any branch: publishes under a throwaway key, prints a one-off URL
scripts/publish.sh             # production: only from an up-to-date, clean main
```

Publishing uses `fdev website update` with the contract WASM pinned in
`published-contract/website_contract.wasm`. The contract key is derived from
that WASM plus `published-contract/website.parameters` (the public key), so
**never change either file**: doing so moves the blog to a new address. The
script checks both against `published-contract/contract-id.txt` before
publishing. Each publish is signed with a version equal to the current Unix
time, which the contract requires to increase.

## The signing key

The private key is not in this repository and must never be committed. On nova
it lives at `/home/ian/code/freenet/keys/blog/website-key.toml` (mode 600,
outside every git repo, covered by both borg backups). `scripts/publish.sh`
refuses to run if the key path resolves inside a git working tree.

To use a different location, copy `.env.example` to `.env` (gitignored) and set
`BLOG_SIGNING_KEY` to the path. `.env` holds the path only, never the key.

Losing the key means the blog can never be updated at this address.
