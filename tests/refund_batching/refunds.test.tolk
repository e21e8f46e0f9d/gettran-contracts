import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@contracts/common/gas/constants"
import "@contracts/common/jetton/messages"
import "@contracts/common/nft/transfers"
import "fixture"

fun assertThreeReceipts(certified: bool) {
    val f = fixture(certified, 3);
    val settled = f.resume();
    assert (txExit(settled) == 0) throw 1001;
    assert (settled.outMessages.size() == 3) throw 1002;
    assert (f.budget() == automaticNftDeliveryRetryReserve(3)) throw 1003;
    var index = 2;
    while (index >= 0) {
        val done = f.ack(index);
        assert (txExit(done) == 0) throw 1004;
        assert (done.outMessages.size() == (index == 0 ? 1 : 0)) throw 1005;
        assert (f.budget() == automaticNftDeliveryRetryReserve(index)) throw 1006;
        index -= 1;
    }
    assert (f.deliveries().isEmpty()) throw 1007;
    assert (testing.getAccountBalance(f.escrow) == MIN_TONS_FOR_STORAGE) throw 1008;
}

get fun `test certified one final refund after three receipts`() {
    assertThreeReceipts(true);
}

get fun `test exact one final refund after three receipts`() {
    assertThreeReceipts(false);
}

fun assertPartialClaim(certified: bool) {
    val f = fixture(certified, 3);
    assert (txExit(f.resume()) == 0) throw 1101;
    val first = f.ack(0);
    assert (first.outMessages.size() == 0) throw 1102;
    val protected = MIN_TONS_FOR_STORAGE + f.budget();
    val result = f.claim(f.beneficiary);
    assert (txExit(result) == 0) throw 1103;
    assert (result.outMessages.size() == 1) throw 1104;
    assert (testing.getAccountBalance(f.escrow) == protected) throw 1105;
    assert (f.deliveries().exists(f.nfts.get(1))) throw 1106;
    val repeated = f.claim(f.beneficiary);
    assert (txExit(repeated) == 4503) throw 1107;
    assert (f.budget() == automaticNftDeliveryRetryReserve(2)) throw 1108;
    assert (txExit(f.ack(1)) == 0) throw 1109;
    assert (txExit(f.ack(2)) == 0) throw 1110;
    assert (f.budget() == 0) throw 1111;
    assert (testing.getAccountBalance(f.escrow) == MIN_TONS_FOR_STORAGE) throw 1112;
    println("partial_claim certified={} gas={} fees={}", certified, result.gasUsed, txFees(result));
}

get fun `test certified claim releases only available surplus with missing receipts`() {
    assertPartialClaim(true);
}

get fun `test exact claim releases only available surplus with missing receipts`() {
    assertPartialClaim(false);
}

fun assertClaimsAuthorization(certified: bool) {
    val f = fixture(certified, 1);
    assert (txExit(f.resume()) == 0) throw 1201;
    val oldBudget = f.budget();
    assert (txExit(f.claim(f.stranger)) == 4501) throw 1202;
    assert (txExit(f.claim(f.beneficiary, grams("0.001"))) == 4502) throw 1203;
    assert (f.budget() == oldBudget) throw 1204;
    assert (f.deliveries().exists(f.nfts.get(0))) throw 1205;
    val opened = fixture(certified, 1, false, true);
    assert (txExit(opened.claim(opened.beneficiary)) == (certified ? 403 : 305)) throw 1206;
}

get fun `test certified rejects foreign underfunded and nonclosed claims`() {
    assertClaimsAuthorization(true);
}

get fun `test exact rejects foreign underfunded and nonclosed claims`() {
    assertClaimsAuthorization(false);
}

fun assertDuplicates(certified: bool) {
    val f = fixture(certified, 1);
    assert (txExit(f.resume()) == 0) throw 1301;
    val query = f.deliveries().get(f.nfts.get(0)).loadValue().queryId;
    val wrong = f.fence(0, query + 1);
    assert (wrong.outMessages.size() == 0 && f.budget() > 0) throw 1302;
    val actual = f.ack(0);
    assert (actual.outMessages.size() == 1 && f.budget() == 0) throw 1303;
    val duplicate = f.fence(0, query);
    assert (txExit(duplicate) == 0 && duplicate.outMessages.size() == 0) throw 1304;
    assert (f.budget() == 0) throw 1305;
}

get fun `test certified stale and duplicate receipts cannot release twice`() {
    assertDuplicates(true);
}

get fun `test exact stale and duplicate receipts cannot release twice`() {
    assertDuplicates(false);
}

fun assertZeroItems(certified: bool) {
    val f = fixture(certified, 0);
    val settled = f.resume();
    assert (txExit(settled) == 0) throw 1401;
    assert (settled.outMessages.size() == 1) throw 1402;
    assert (f.budget() == 0) throw 1403;
    assert (testing.getAccountBalance(f.escrow) == MIN_TONS_FOR_STORAGE) throw 1404;
}

get fun `test certified without nft refunds immediately`() {
    assertZeroItems(true);
}

get fun `test exact without nft refunds immediately`() {
    assertZeroItems(false);
}

fun benchmark(certified: bool, previous: bool, native: bool = false): (int, int, int) {
    val f = fixture(
        certified,
        3,
        previous,
        false,
        false,
        0,
        native,
    );
    val initial = f.resume();
    assert (txExit(initial) == 0) throw 1501;
    var gas = initial.gasUsed;
    var fees = txFees(initial) as int;
    var refunds = initial.outMessages.size() - (native ? 5 : 3);
    var i = 0;
    while (i < 3) {
        val query = f.deliveryQuery(i);
        val excess = f.receive(f.nfts.get(i), JettonExcesses { queryId: query }.toCell());
        val done = f.fence(i, query);
        assert (txExit(done) == 0 && txExit(excess) == 0) throw 1502;
        gas += excess.gasUsed + done.gasUsed;
        fees += txFees(excess) + txFees(done);
        refunds += done.outMessages.size();
        i += 1;
    }
    println(
        "benchmark certified={} previous={} gas={} rawtxfees={} refunds={}",
        certified,
        previous,
        gas,
        fees,
        refunds,
    );
    return (gas, fees, refunds);
}

fun assertBenchmark(certified: bool) {
    val (oldGas, oldFees, oldCount) = benchmark(certified, true);
    val (newGas, newFees, newCount) = benchmark(certified, false);
    assert (oldCount == 4 && newCount == 1) throw 1503;
    assert (newGas < oldGas && newFees < oldFees) throw 1504;
    println(
        "savings certified={} gas={} own_fees={}",
        certified,
        oldGas - newGas,
        oldFees - newFees,
    );
}

get fun `test certified actual old new same config gas comparison`() {
    assertBenchmark(true);
}

get fun `test exact actual old new same config gas comparison`() {
    assertBenchmark(false);
}

fun assertUsdtProtected(certified: bool) {
    val f = fixture(certified, 3, false, false, true);
    assert (txExit(f.resume()) == 0) throw 1601;
    val storage = net.runGetMethod<coins>(f.escrow, "usdt_recovery_storage_reserve");
    assert (storage > MIN_TONS_FOR_STORAGE) throw 1602;
    assert (txExit(f.ack(1)) == 0) throw 1603;
    val before = f.budget();
    val result = f.claim(f.beneficiary);
    assert (txExit(result) == 0) throw 1604;
    val actualStorage = net.runGetMethod<coins>(f.escrow, "usdt_recovery_storage_reserve");
    assert (testing.getAccountBalance(f.escrow) >= actualStorage + before) throw 1605;
    assert (f.budget() == before && !f.deliveries().isEmpty()) throw 1606;
    assert (result.gasUsed < 120000) throw 1607;
    println("usdt_claim certified={} gas={} storage={}", certified, result.gasUsed, actualStorage);
}

get fun `test certified usdt storage and pending retries stay protected on claim`() {
    assertUsdtProtected(true);
}

get fun `test exact usdt storage and pending retries stay protected on claim`() {
    assertUsdtProtected(false);
}

fun assertOrder(certified: bool, first: int, second: int, third: int) {
    val f = fixture(
        certified,
        3,
        false,
        false,
        false,
        first * 9 + second * 3 + third,
    );
    assert (txExit(f.resume()) == 0) throw 1701;
    assert (f.ack(first).outMessages.size() == 0) throw 1702;
    assert (f.ack(second).outMessages.size() == 0) throw 1703;
    assert (f.ack(third).outMessages.size() == 1) throw 1704;
}

get fun `test every receipt ordering flushes exactly once`() {
    var runtime = 0;
    while (runtime < 2) {
        assertOrder(runtime == 1, 0, 1, 2);
        assertOrder(runtime == 1, 0, 2, 1);
        assertOrder(runtime == 1, 1, 0, 2);
        assertOrder(runtime == 1, 1, 2, 0);
        assertOrder(runtime == 1, 2, 0, 1);
        assertOrder(runtime == 1, 2, 1, 0);
        runtime += 1;
    }
}

fun assertMaxClaim(certified: bool) {
    val f = fixture(certified, 100, false, false, true);
    val settled = f.resume();
    println("max initial certified={} exit={} gas={}", certified, txExit(settled), settled.gasUsed);
    assert (txExit(settled) == 0) throw 1801;
    assert (settled.outMessages.size() == 100) throw 1802;
    val before = f.budget();
    val claim = f.claim(f.beneficiary);
    assert (txExit(claim) == 0) throw 1803;
    assert (claim.gasUsed < 120000) throw 1804;
    assert (f.budget() == before) throw 1805;
    println("max100usdtclaim certified={} gas={}", certified, claim.gasUsed);
}

get fun `test certified max100 usdt claim stays within funded gas bound`() {
    assertMaxClaim(true);
}

get fun `test exact max100 usdt claim stays within funded gas bound`() {
    assertMaxClaim(false);
}

fun assertNativeBenchmark(certified: bool) {
    val (oldGas, oldFees, oldCount) = benchmark(certified, true, true);
    val (newGas, newFees, newCount) = benchmark(certified, false, true);
    assert (oldCount == 4 && newCount == 1) throw 1511;
    println(
        "native_savings certified={} gas={} own_fees={}",
        certified,
        oldGas - newGas,
        oldFees - newFees,
    );
}

get fun `test certified native payment old new same config gas comparison`() {
    assertNativeBenchmark(true);
}

get fun `test exact native payment old new same config gas comparison`() {
    assertNativeBenchmark(false);
}
