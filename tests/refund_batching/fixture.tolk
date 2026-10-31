import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/types/transaction"
import "@contracts/certified_offer_escrow/enums"
import "@contracts/certified_offer_escrow/messages"
import "@contracts/certified_offer_escrow/storage"
import "@contracts/offer_escrow/enums"
import "@contracts/offer_escrow/messages"
import "@contracts/offer_escrow/storage"
import "@contracts/common/comments/messages"
import "@contracts/common/jetton/messages"
import "@contracts/common/nft/deliveries"
import "@contracts/common/nft/deposits"
import "@contracts/common/nft/enums"
import "@contracts/common/nft/messages"
import "@contracts/common/offer/deposits"
import "@contracts/common/offer/enums"
import "@contracts/common/offer/messages"
import "@contracts/common/offer/terms"
import "@contracts/common/offer/wallets"

struct RefundFixture {
    escrow: address
    beneficiary: address
    stranger: address
    maker: address
    nfts: array<address>
    certified: bool
    previous: bool
}

fun RefundFixture.state(self): cell {
    val account = testing.getAccountState(self.escrow)!;
    val state = account.storage.state;
    assert (state is TlbAccountStateActive) throw 990;
    return state.stateInit.data!;
}

fun RefundFixture.budget(self): coins {
    return self.certified
        ? CertifiedOfferEscrowStorage.fromCell(self.state()).automaticRecoveryBudget
        : OfferEscrowStorage.fromCell(self.state()).automaticRecoveryBudget;
}

fun RefundFixture.deliveries(self): NftDeliveries {
    return self.certified
        ? CertifiedOfferEscrowStorage.fromCell(self.state()).deposits.load().nftDeliveries
        : OfferEscrowStorage.fromCell(self.state()).deposits.load().nftDeliveries;
}

fun txExit(result: SendResult): int {
    val description = result.tx.load().description.load();
    assert (description is TlbTransOrd) throw 991;
    val compute = description.computePh;
    assert (compute is TlbTrComputeVm) throw 992;
    return compute.data.load().exitCode;
}

fun txFees(result: SendResult): coins {
    return result.tx.load().totalFees.grams;
}

fun RefundFixture.receive(
    self,
    from: address,
    body: cell,
    value: coins = grams("0.05"),
): SendResult {
    val result = testing.processSingleTraceStep(
        from,
        createMessage({
            bounce: false,
            dest: self.escrow,
            value,
            body,
        }),
    );
    self.assertAllocationSum();
    return result;
}

fun RefundFixture.resume(self): SendResult {
    return self.receive(
        self.beneficiary,
        self.certified
            ? ResumeCertifiedSettlement { queryId: 7 }.toCell()
            : ResumeSettlement { queryId: 7 }.toCell(),
        grams("0.2"),
    );
}

fun RefundFixture.fence(self, index: int, queryId: uint64): SendResult {
    return self.receive(
        self.nfts.get(index),
        NftReportStaticData {
            queryId,
            index,
            collection: null,
        }.toCell(),
    );
}

fun RefundFixture.ack(self, index: int): SendResult {
    val queryId = self.deliveryQuery(index);
    val excess = self.receive(self.nfts.get(index), JettonExcesses { queryId }.toCell());
    assert (txExit(excess) == 0) throw 993;
    return self.fence(index, queryId);
}

fun RefundFixture.claim(self, from: address, value: coins = grams("0.1")): SendResult {
    return self.receive(from, ClaimEscrowSurplus { queryId: 19 }.toCell(), value);
}

fun fixture(
    certified: bool,
    count: int,
    previous: bool = false,
    open: bool = false,
    usdt: bool = false,
    salt: int = 0,
    native: bool = false,
): RefundFixture {
    val maker = testing.treasury("maker").address;
    val beneficiary = testing.treasury("beneficiary").address;
    val stranger = testing.treasury("stranger").address;
    var nfts: array<address> = [];
    var makerItems: ItemDeposits = [];
    var index = 0;
    while (index < count) {
        val nft = address.fromWorkchainAndHash(0, index + 100);
        nfts.push(nft);
        makerItems.set(nft, { refundRecipient: maker, depositor: maker });
        index += 1;
    }
    val parties = OfferEscrowParties {
        makerWallets: singleOfferWallet(maker),
        makerSettlementWallet: maker,
        addresseeWallets: [],
    }.toCell();
    val config = EscrowConfig {
        feeTreasury: stranger,
        unexpectedNftRecoveryAuthority: stranger,
    }.toCell();
    val payment: Cell<PaymentTerms>? = usdt
        ? PaymentTerms {
            asset: PaymentAsset.Usdt,
            payer: OfferSide.Taker,
            amount: grams("1"),
            marketplaceFee: 0,
        }.toCell()
        : native
            ? PaymentTerms {
                asset: PaymentAsset.Ton,
                payer: OfferSide.Taker,
                amount: grams("1"),
                marketplaceFee: grams("0.1"),
            }.toCell()
            : null;
    val deposits = OfferEscrowDeposits {}.toCell();
    var state: cell;
    var code: cell;
    if (certified) {
        val details = CertifiedExecutionAttemptDetails {
            contributorWallets: singleOfferWallet(beneficiary),
            takerSettlementWallet: beneficiary,
            takerTonFee: 0,
            delivery: null,
        }.toCell();
        state = CertifiedOfferEscrowStorage {
            status: open
                ? CertifiedOfferEscrowStatus.Open
                : CertifiedOfferEscrowStatus.PayoutConfirmed,
            expiresAt: testing.getNow() + 3600,
            executionAttemptTtl: 600,
            deposits,
            offerExecutionNumber: 0,
            payoutQueryId: 0,
            certifierPublicKey: 1,
            terms: CertifiedOfferTerms {
                offerId: 15 + salt,
                makerItemCount: count,
                takerItemCount: 0,
                parties,
                payment,
                makerTonFee: 0,
                policy: CertifiedOfferPolicy {
                    takerRequirementCommitment: 0,
                    makerDelivery: null,
                }.toCell(),
                config,
            }.toCell(),
            makerItems,
            executionAttempt: CertifiedOfferExecutionAttempt {
                number: 0,
                certificateHash: 1,
                validUntil: testing.getNow() + 600,
                confirmedContributorWallets: singleOfferWallet(beneficiary),
                deposits: { total: 0, contributions: [] },
                details,
                excessRecipient: beneficiary,
            }.toCell(),
            reserveRefundRecipient: beneficiary,
        }.toCell();
        code = previous
            ? build(
                "PreviousCertified",
                "tests/refund_batching/fixtures/CertifiedOfferEscrow.v1.boc",
            )
            : build("CertifiedOfferEscrow");
    } else {
        state = OfferEscrowStorage {
            status: open ? OfferEscrowStatus.Open : OfferEscrowStatus.PayoutConfirmed,
            areTermsValidated: true,
            expiresAt: testing.getNow() + 3600,
            executionAttemptTtl: 600,
            deposits,
            offerExecutionNumber: 0,
            payoutQueryId: 0,
            terms: OfferEscrowTerms {
                offerId: 15 + salt,
                makerItemCount: count,
                takerItemCount: 0,
                parties,
                payment,
                makerTonFee: 0,
                config,
            }.toCell(),
            items: OfferEscrowItems { maker: makerItems }.toCell(),
            executionAttempt: OfferExecutionAttempt {
                number: 0,
                allowedContributorWallets: singleOfferWallet(beneficiary),
                confirmedContributorWallets: singleOfferWallet(beneficiary),
                takerSettlementWallet: beneficiary,
                validUntil: testing.getNow() + 600,
                deposits: { total: 0, contributions: [] },
            }.toCell(),
            reserveRefundRecipient: beneficiary,
        }.toCell();
        code = previous
            ? build("PreviousExact", "tests/refund_batching/fixtures/OfferEscrow.v1.boc")
            : build("OfferEscrow");
    }
    val init: AutoDeployAddress = { workchain: 0, stateInit: { code, data: state } };
    val deployed = testing.processSingleTraceStep(
        beneficiary,
        createMessage({
            bounce: false,
            dest: init,
            value: grams("20"),
            body: NftReportStaticData {
                queryId: 0,
                index: 0,
                collection: null,
            },
        }),
    );
    assert (txExit(deployed) == 0) throw 994;
    return {
        escrow: init.calculateAddress(),
        beneficiary,
        maker,
        stranger,
        nfts,
        certified,
        previous,
    };
}

// Только для чтения замороженного старого BOC в сравнительном benchmark, не для production.
struct LegacyNftDelivery {
    recipient: address
    comment: Cell<TextComment>? = null
    queryId: uint64
    sponsor: address? = null
    hasReceipt: bool = false
    automaticAttempts: uint8 = 0
    status: NftDeliveryStatus = NftDeliveryStatus.Pending
}

fun RefundFixture.deliveryQuery(self, index: int): uint64 {
    if (self.previous) {
        val legacy = self.deliveries() as unknown as map<address, LegacyNftDelivery>;
        return legacy.get(self.nfts.get(index)).loadValue().queryId;
    }
    return self.deliveries().get(self.nfts.get(index)).loadValue().queryId;
}

fun RefundFixture.bounce(self, index: int): SendResult {
    val query = self.deliveryQuery(index);
    return testing.processSingleTraceStep(
        self.nfts.get(index),
        createMessage({
            bounce: false,
            dest: self.escrow,
            value: grams("0.03"),
            body: beginCell()
                .storeUint(0xffffffff, 32)
                .storeUint(0x5fcc3d14, 32)
                .storeUint(query, 64)
                .endCell(),
        }).bounced(),
    );
}

// Только локальный sandbox: имитирует уже записанный chain state, не выполняет write в сети.
fun RefundFixture.seedRecordedState(self, data: cell) {
    var shard = testing.getShardAccount(self.escrow)!;
    var account = shard.account.load();
    assert (account is TlbAccountInfo) throw 995;
    var state = account.storage.state;
    assert (state is TlbAccountStateActive) throw 996;
    state.stateInit.data = data;
    account.storage.state = state;
    shard.account = account.toCell() as cell as Cell<TlbAccount>;
    testing.setShardAccount(self.escrow, shard);
}

fun RefundFixture.assertAllocationSum(self) {
    if (self.previous) {
        return;
    }
    val deliveries = self.deliveries();
    var entry = deliveries.findFirst();
    var total = 0;
    while (entry.isFound) {
        total += entry.loadValue().automaticReserve;
        entry = deliveries.iterateNext(entry);
    }
    assert (total == self.budget()) throw 9700;
}
