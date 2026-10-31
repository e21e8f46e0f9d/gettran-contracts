import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/types/message"
import "@contracts/common/gas/constants"
import "@contracts/common/jetton/messages"
import "@contracts/common/nft/constants"
import "@contracts/common/nft/enums"
import "@contracts/common/nft/messages"
import "@contracts/common/nft/recovery_messages"
import "@contracts/common/nft/transfers"
import "fixture"

fun assertManualSponsor(certified: bool) {
    val f = fixture(certified, 2);
    assert (txExit(f.resume()) == 0) throw 2001;
    val allocation = f.deliveries().get(f.nfts.get(0)).loadValue().automaticReserve;
    assert (allocation > 0) throw 2002;
    assert (txExit(f.bounce(0)) == 0) throw 2003;
    assert (
        f.deliveries().get(f.nfts.get(0)).loadValue().status == NftDeliveryStatus.Failed
    ) throw 2004;
    val retry = f.receive(
        f.stranger,
        RetryNftDelivery {
            queryId: 17,
            nft: f.nfts.get(0),
        }.toCell(),
        grams("0.2"),
    );
    assert (txExit(retry) == 0) throw 2005;
    assert (
        f.deliveries().get(f.nfts.get(0)).loadValue().automaticReserve == allocation
    ) throw 2006;
    assert (f.ack(1).outMessages.size() == 0) throw 2007;
    val done = f.ack(0);
    assert (txExit(done) == 0) throw 2008;
    assert (done.outMessages.size() == 2) throw 2009;
    val sponsor = done.outMessages.atCell(0) as Cell<TlbMessageRelaxedGeneric>;
    val beneficiary = done.outMessages.atCell(1) as Cell<TlbMessageRelaxedGeneric>;
    assert (sponsor.load().info.dest == f.stranger) throw 2010;
    assert (beneficiary.load().info.dest == f.beneficiary) throw 2011;
    assert (f.budget() == 0) throw 2012;
    assert (testing.getAccountBalance(f.escrow) == MIN_TONS_FOR_STORAGE) throw 2013;
}

get fun `test certified manual retry retains and releases its own reserve`() {
    assertManualSponsor(true);
}

get fun `test exact manual retry retains and releases its own reserve`() {
    assertManualSponsor(false);
}

fun assertManualConfirm(certified: bool) {
    val f = fixture(certified, 2);
    assert (txExit(f.resume()) == 0) throw 2101;
    assert (txExit(f.bounce(0)) == 0) throw 2102;
    val forbidden = f.receive(f.stranger, ConfirmNftDelivery { nft: f.nfts.get(0) }.toCell());
    assert (txExit(forbidden) == (certified ? 430 : 325)) throw 2103;
    assert (f.budget() == automaticNftDeliveryRetryReserve(2)) throw 2104;
    val actual = f.receive(f.beneficiary, ConfirmNftDelivery { nft: f.nfts.get(0) }.toCell());
    assert (txExit(actual) == 0) throw 2105;
    assert (f.budget() == automaticNftDeliveryRetryReserve(1)) throw 2106;
    assert (f.ack(1).outMessages.size() == 1) throw 2107;
    assert (f.budget() == 0) throw 2108;
}

get fun `test certified authorized manual completion releases only its reserve`() {
    assertManualConfirm(true);
}

get fun `test exact authorized manual completion releases only its reserve`() {
    assertManualConfirm(false);
}

fun assertReconstructed(certified: bool) {
    val f = fixture(certified, 2);
    assert (txExit(f.resume()) == 0) throw 2201;
    assert (txExit(f.ack(0)) == 0) throw 2202;
    val before = f.budget();
    val retry = f.receive(
        f.stranger,
        RetryNftDelivery {
            queryId: 18,
            nft: f.nfts.get(0),
        }.toCell(),
        grams("0.2"),
    );
    assert (txExit(retry) == 0) throw 2203;
    assert (f.deliveries().get(f.nfts.get(0)).loadValue().automaticReserve == 0) throw 2204;
    val done = f.ack(0);
    assert (txExit(done) == 0) throw 2205;
    assert (f.budget() == before) throw 2206;
    assert (done.outMessages.size() == 1) throw 2207;
    assert (f.deliveries().exists(f.nfts.get(1))) throw 2208;
}

get fun `test certified reconstructed retry cannot release another nft budget`() {
    assertReconstructed(true);
}

get fun `test exact reconstructed retry cannot release another nft budget`() {
    assertReconstructed(false);
}

fun assertAutomatic(certified: bool) {
    val f = fixture(certified, 2);
    assert (txExit(f.resume()) == 0) throw 2301;
    assert (txExit(f.bounce(0)) == 0) throw 2302;
    val before = f.budget();
    val cursor = testing.createExternalTraceIterationCursor(
        net.createExternalMessage(
            f.escrow,
            TriggerNftDeliveryRetry {
                offerId: 15,
                nft: f.nfts.get(0),
                deliveryQueryId: f.deliveryQuery(0),
            },
        ),
    );
    val results = cursor.executeN(1);
    cursor.close();
    assert (txExit(results.at(0)) == 0) throw 2303;
    assert (f.deliveries().get(f.nfts.get(0)).loadValue().automaticReserve == 0) throw 2304;
    assert (f.deliveries().get(f.nfts.get(0)).loadValue().automaticAttempts == 1) throw 2305;
    assert (f.budget() == before - requiredNftRetryValue()) throw 2306;
    assert (txExit(f.ack(0)) == 0) throw 2307;
    assert (f.budget() == automaticNftDeliveryRetryReserve(1)) throw 2308;
    assert (txExit(f.ack(1)) == 0 && f.budget() == 0) throw 2309;
}

get fun `test certified automatic retry consumes its allocation exactly once`() {
    assertAutomatic(true);
}

get fun `test exact automatic retry consumes its allocation exactly once`() {
    assertAutomatic(false);
}

fun assertUnexpected(certified: bool) {
    val f = fixture(certified, 2);
    assert (txExit(f.resume()) == 0) throw 2401;
    val before = f.budget();
    testing.setNow(testing.getNow() + UNEXPECTED_NFT_RECOVERY_DELAY + 1);
    val nft = address("0:0000000000000000000000000000000000000000000000000000000000009999");
    val recover = f.receive(
        f.stranger,
        RecoverUnexpectedNft {
            recoveryId: 1,
            nft,
            recipient: f.stranger,
        }.toCell(),
        grams("0.2"),
    );
    assert (txExit(recover) == 0) throw 2402;
    assert (f.deliveries().get(nft).loadValue().automaticReserve == 0) throw 2403;
    val query = f.deliveries().get(nft).loadValue().queryId;
    assert (txExit(f.receive(nft, JettonExcesses { queryId: query }.toCell())) == 0) throw 2404;
    val done = f.receive(
        nft,
        NftReportStaticData {
            queryId: query,
            index: 9999,
            collection: null,
        }.toCell(),
    );
    assert (txExit(done) == 0) throw 2405;
    assert (f.budget() == before) throw 2406;
    assert (f.deliveries().exists(f.nfts.get(0))) throw 2407;
    assert (done.outMessages.size() == 1) throw 2408;
}

get fun `test certified unexpected nft recovery cannot spend original allocations`() {
    assertUnexpected(true);
}

get fun `test exact unexpected nft recovery cannot spend original allocations`() {
    assertUnexpected(false);
}

fun assertManualLast(certified: bool) {
    val f = fixture(certified, 1);
    assert (txExit(f.resume()) == 0) throw 2501;
    assert (txExit(f.bounce(0)) == 0) throw 2502;
    val result = f.receive(f.beneficiary, ConfirmNftDelivery { nft: f.nfts.get(0) }.toCell());
    assert (txExit(result) == 0) throw 2503;
    assert (f.budget() == 0 && f.deliveries().isEmpty()) throw 2504;
    assert (testing.getAccountBalance(f.escrow) == MIN_TONS_FOR_STORAGE) throw 2505;
    assert (result.outMessages.size() == 2) throw 2506;
}

get fun `test certified last manual completion flushes previously held surplus`() {
    assertManualLast(true);
}

get fun `test exact last manual completion flushes previously held surplus`() {
    assertManualLast(false);
}
