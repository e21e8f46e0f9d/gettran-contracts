# Gettran Contracts

TON smart contracts for Gettran. Version 1.0.0.

- `OfferEscrow`: settlement with fixed on-chain terms.
- `CertifiedOfferEscrow`: settlement requiring a signed execution certificate.
- `UsdtDepositVault`: USDT deposits and withdrawals.

## Build

Requires Acton 1.2.1.

```sh
acton build
```

The source uses the mainnet USDT profile.

## Trust

Certified escrow depends on an immutable certifier key. A funded attempt requiring
certifier approval can remain locked until a signed decision is provided; there is
no automatic timeout refund or key rotation.

## License

MIT. See [LICENSE](LICENSE).

## Internal escrow code profile 2 candidate

The public product release remains version 1.0.0. Internal code profile 2 is a distinct
immutable ABI/storage identity, not a product-version announcement.

See [refund-batching-v2.md](docs/refund-batching-v2.md) for the single final change refund,
caller-funded surplus claim, version boundary and local checks. This candidate is not a
production activation and does not upgrade existing immutable v1 escrows.
