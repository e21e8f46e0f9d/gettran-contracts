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
