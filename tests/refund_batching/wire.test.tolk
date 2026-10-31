import "@acton/boc"
import "@acton/fs"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/types/message"
import "@contracts/common/gas/constants"
import "@contracts/common/nft/deliveries"
import "@contracts/common/nft/enums"
import "@contracts/common/nft/transfers"
import "@contracts/common/offer/messages"
import "@contracts/common/offer/surplus"
import "fixture"

get fun `test canonical v2 wire golden encodes exact reserve and fixed beneficiary`() {
    val recordCell = boc.decode(fs.readBytes("tests/refund_batching/fixtures/delivery-v2.boc")!)!;
    val record = NftDelivery.fromCell(recordCell);
    assert (record.automaticReserve == 123456789 && record.queryId == 42) throw 3501;
    assert (record.status == NftDeliveryStatus.Failed && record.sponsor == null) throw 3502;
    assert (record.toCell().hash() == recordCell.hash()) throw 3503;
    val claimCell = boc.decode(fs.readBytes("tests/refund_batching/fixtures/claim-v2.boc")!)!;
    val claim = ClaimEscrowSurplus.fromCell(claimCell);
    assert (claim.queryId == 42) throw 3504;
    assert (claim.toCell().hash() == claimCell.hash()) throw 3505;
}

get fun `test forged recipient tail cannot redirect a v2 claim`() {
    val f = fixture(true, 1);
    assert (txExit(f.resume()) == 0) throw 3601;
    val forged = beginCell()
        .storeSlice(ClaimEscrowSurplus { queryId: 1 }.toCell().beginParse())
        .storeAddress(f.stranger)
        .endCell();
    val claimed = f.receive(f.beneficiary, forged, grams("0.1"));
    assert (txExit(claimed) == 0 && claimed.outMessages.size() == 1) throw 3602;
    val result = (claimed.outMessages.atCell(0) as Cell<TlbMessageRelaxedGeneric>).load();
    assert (result.info.dest == f.beneficiary) throw 3603;
}

fun assertTinySurplus(certified: bool) {
    val f = fixture(certified, 1);
    assert (txExit(f.resume()) == 0) throw 3701;
    assert (txExit(f.claim(f.beneficiary)) == 0) throw 3702;
    testing.topUp(f.escrow, 100);
    val quote = net.runGetMethod<EscrowSurplusClaimInfo>(f.escrow, "surplus_claim");
    assert (quote.available == 100) throw 3703;
    val result = f.claim(f.beneficiary);
    assert (txExit(result) == 0 && txFees(result) > 100) throw 3704;
    // Технически доступно, экономически невыгодно: UI обязан предупреждать, а не запускать сам.
    assert (f.budget() == automaticNftDeliveryRetryReserve(1)) throw 3705;
}

get fun `test certified tiny free amount stays accessible without subsidising claim`() {
    assertTinySurplus(true);
}

get fun `test exact tiny free amount stays accessible without subsidising claim`() {
    assertTinySurplus(false);
}

get fun `test stale surplus claim bounces its caller funding after final refund`() {
    val f = fixture(true, 0);
    assert (txExit(f.resume()) == 0) throw 3801;
    val stale = testing.processSingleTraceStep(
        f.beneficiary,
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            dest: f.escrow,
            value: grams("0.1"),
            body: ClaimEscrowSurplus { queryId: 42 },
        }),
    );
    assert (txExit(stale) == 4503) throw 3802;
    assert (stale.outMessages.size() == 1) throw 3803;
    val bounced = (stale.outMessages.atCell(0) as Cell<TlbMessageRelaxedGeneric>).load();
    assert (bounced.info.bounced && bounced.info.dest == f.beneficiary) throw 3804;
    assert (testing.getAccountBalance(f.escrow) == MIN_TONS_FOR_STORAGE) throw 3805;
}
