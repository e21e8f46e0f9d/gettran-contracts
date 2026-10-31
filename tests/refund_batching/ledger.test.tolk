import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@contracts/certified_offer_escrow/storage"
import "@contracts/offer_escrow/storage"
import "@contracts/usdt_deposit_vault/enums"
import "@contracts/usdt_deposit_vault/storage"
import "@contracts/common/nft/transfers"
import "@contracts/common/offer/enums"
import "@contracts/common/offer/surplus"
import "@contracts/common/usdt/deposits"
import "@contracts/common/usdt/enums"
import "fixture"

fun assertFullLedger(certified: bool) {
    val f = fixture(certified, 100, false, false, true);
    assert (txExit(f.resume()) == 0) throw 3301;
    var ledger = UsdtDeposits {};
    var i = 0;
    while (i < 32) {
        val terms = UsdtDepositTerms {
            escrow: f.escrow,
            contributor: f.beneficiary,
            offerExecutionNumber: 0,
            side: OfferSide.Taker,
            purpose: UsdtDepositPurpose.Principal,
            nonce: i,
            amount: grams("0.01"),
        }.toCell();
        ledger.add(terms);
        val key = usdtDepositInit(terms).calculateAddress();
        var record = ledger.entries.get(key).loadValue();
        record.assignmentStatus = UsdtDepositAssignmentStatus.Assigned;
        record.selectedAttempt = 1;
        ledger.entries.set(key, record);
        i += 1;
    }
    ledger.assignedCount = 32;
    if (certified) {
        var state = CertifiedOfferEscrowStorage.fromCell(f.state());
        var deposits = state.deposits.load();
        deposits.usdt = ledger;
        state.deposits = deposits.toCell();
        f.seedRecordedState(state.toCell());
    } else {
        var state = OfferEscrowStorage.fromCell(f.state());
        var deposits = state.deposits.load();
        deposits.usdt = ledger;
        state.deposits = deposits.toCell();
        f.seedRecordedState(state.toCell());
    }
    val budget = f.budget();
    val quote = net.runGetMethod<EscrowSurplusClaimInfo>(f.escrow, "surplus_claim");
    assert (quote.beneficiary == f.beneficiary && quote.available > 0) throw 3302;
    val claimed = f.claim(f.beneficiary);
    assert (txExit(claimed) == 0) throw 3303;
    assert (claimed.gasUsed < 120000) throw 3304;
    assert (f.budget() == budget) throw 3305;
    val storage = net.runGetMethod<coins>(f.escrow, "usdt_recovery_storage_reserve");
    assert (testing.getAccountBalance(f.escrow) >= storage + budget) throw 3306;
    println(
        "max100nft32usdtclaim certified={} gas={} minimumValue={}",
        certified,
        claimed.gasUsed,
        quote.minimumMessageValue,
    );
}

get fun `test certified max100 nft plus32 recorded usdt claim gas and reserve`() {
    assertFullLedger(true);
}

get fun `test exact max100 nft plus32 recorded usdt claim gas and reserve`() {
    assertFullLedger(false);
}

fun assertIndependentClaims(certified: bool) {
    val f = fixture(certified, 3);
    assert (txExit(f.resume()) == 0) throw 3401;
    assert (txExit(f.ack(0)) == 0) throw 3402;
    assert (txExit(f.claim(f.beneficiary)) == 0) throw 3403;
    assert (txExit(f.ack(1)) == 0) throw 3404;
    assert (txExit(f.claim(f.beneficiary)) == 0) throw 3405;
    // Третий NFT намеренно никогда не отвечает: его бюджет остаётся, уже свободная сдача не заперта.
    assert (f.budget() == automaticNftDeliveryRetryReserve(1)) throw 3406;
    assert (f.deliveries().exists(f.nfts.get(2))) throw 3407;
    val noFree = net.runGetMethod<EscrowSurplusClaimInfo>(f.escrow, "surplus_claim");
    assert (noFree.available == 0) throw 3408;
}

get fun `test certified one never answered nft cannot lock earlier free change`() {
    assertIndependentClaims(true);
}

get fun `test exact one never answered nft cannot lock earlier free change`() {
    assertIndependentClaims(false);
}
