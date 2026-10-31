import "@acton/emulation/network"
import "@acton/types/message"
import "@contracts/offer_escrow/messages"
import "@contracts/offer_escrow/storage"
import "@contracts/common/comments/messages"
import "@contracts/common/nft/deposits"
import "@contracts/common/nft/messages"
import "@contracts/common/offer/enums"
import "@contracts/common/offer/messages"
import "@contracts/common/offer/terms"
import "@contracts/common/offer/wallets"
import "fixture"

fun assertNativePrincipal(certified: bool) {
    val f = fixture(
        certified,
        3,
        false,
        false,
        false,
        0,
        true,
    );
    val settled = f.resume();
    assert (txExit(settled) == 0) throw 2801;
    assert (settled.outMessages.size() == 5) throw 2802;
    val principal = (settled.outMessages.atCell(3) as Cell<TlbMessageRelaxedGeneric>).load();
    val fee = (settled.outMessages.atCell(4) as Cell<TlbMessageRelaxedGeneric>).load();
    assert (
        principal.info.dest == f.maker && principal.info.value.grams == grams("0.9")
    ) throw 2803;
    assert (fee.info.dest == f.stranger && fee.info.value.grams == grams("0.1")) throw 2804;
    assert (f.ack(0).outMessages.size() == 0) throw 2805;
    assert (f.ack(2).outMessages.size() == 0) throw 2806;
    assert (f.ack(1).outMessages.size() == 1) throw 2807;
}

get fun `test certified batching preserves principal and marketplace fee`() {
    assertNativePrincipal(true);
}

get fun `test exact batching preserves principal and marketplace fee`() {
    assertNativePrincipal(false);
}

fun assertCancel(certified: bool) {
    val f = fixture(certified, 3, false, true);
    val cancelled = f.receive(f.maker, Cancel { queryId: 10 }.toCell(), grams("0.2"));
    assert (txExit(cancelled) == 0) throw 2901;
    assert (cancelled.outMessages.size() == 3) throw 2902;
    assert (f.ack(1).outMessages.size() == 0) throw 2903;
    assert (f.ack(0).outMessages.size() == 0) throw 2904;
    assert (f.ack(2).outMessages.size() == 1) throw 2905;
    assert (f.budget() == 0) throw 2906;
}

get fun `test certified cancel nft refunds also share one surplus return`() {
    assertCancel(true);
}

get fun `test exact cancel nft refunds also share one surplus return`() {
    assertCancel(false);
}

get fun `test exact single nft native sale fast path does not emit early surplus`() {
    val f = fixture(
        false,
        1,
        false,
        true,
        false,
        0,
        true,
    );
    val bought = f.receive(
        f.beneficiary,
        BuyOffer {
            queryId: 12,
            offerExecutionNumber: 0,
            paymentAmount: grams("1"),
            allowedContributorWallets: singleOfferWallet(f.beneficiary),
            takerSettlementWallet: f.beneficiary,
        }.toCell(),
        grams("1.2"),
    );
    assert (txExit(bought) == 0) throw 3001;
    assert (bought.outMessages.size() == 3) throw 3002;
    assert (f.ack(0).outMessages.size() == 1) throw 3003;
}

get fun `test exact whole lot native transfer fast path does not emit early surplus`() {
    val f = fixture(
        false,
        3,
        false,
        true,
        false,
        0,
        true,
    );
    val bought = f.receive(
        f.beneficiary,
        TextComment { text: "".literalSlice() }.toCell(),
        grams("1.2"),
    );
    assert (txExit(bought) == 0) throw 3101;
    assert (bought.outMessages.size() == 5) throw 3102;
    assert (f.ack(2).outMessages.size() == 0) throw 3103;
    assert (f.ack(0).outMessages.size() == 0) throw 3104;
    assert (f.ack(1).outMessages.size() == 1) throw 3105;
}

get fun `test exact single nft purchase fast path does not emit early surplus`() {
    val f = fixture(
        false,
        1,
        false,
        true,
        false,
        0,
        true,
    );
    var storage = OfferEscrowStorage.fromCell(f.state());
    var terms = storage.terms.load();
    terms.makerItemCount = 0;
    terms.takerItemCount = 1;
    terms.payment = PaymentTerms {
        asset: PaymentAsset.Ton,
        payer: OfferSide.Maker,
        amount: grams("1"),
        marketplaceFee: grams("0.1"),
    }.toCell();
    storage.terms = terms.toCell();
    var pending: ItemDeposits = [];
    pending.set(f.nfts.get(0), { refundRecipient: f.beneficiary, depositor: null });
    storage.items = OfferEscrowItems {
        taker: pending,
        takerTemplate: pending,
    }.toCell();
    storage.executionAttempt = null;
    var deposits = storage.deposits.load();
    var contributions: MoneyContributions = [];
    contributions.add(f.maker, grams("1"));
    deposits.maker = { total: grams("1"), contributions };
    storage.deposits = deposits.toCell();
    f.seedRecordedState(storage.toCell());
    val assigned = f.receive(
        f.nfts.get(0),
        NftOwnershipAssigned {
            queryId: 13,
            previousOwner: f.beneficiary,
            forwardPayload: beginCell().storeBool(false).endCell().beginParse(),
        }.toCell(),
        grams("0.2"),
    );
    assert (txExit(assigned) == 0) throw 3201;
    assert (assigned.outMessages.size() == 3) throw 3202;
    assert (f.ack(0).outMessages.size() == 1) throw 3203;
}
