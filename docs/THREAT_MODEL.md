# Threat model

Trusted components are the signed app, hook bridge and per-user service. Agent arguments, repository instructions, tool responses and model findings are untrusted data. Same-user processes can disable hooks; this is not tamper-proof protection.

Critical denials require local evidence. Model text can neither grant permissions nor execute instructions. Approval binding includes provider, session, turn, event, source invocation and digest of the original action. Terminal approvals cannot be reused, and the expiration boundary rejects approval.

Coverage must be derived from configuration, signed binary, host trust, exact-version compatibility and an actual recent tested pre-tool callback. Fixture decoding or a config-file check never proves coverage. Unknown execution remains unknown.
