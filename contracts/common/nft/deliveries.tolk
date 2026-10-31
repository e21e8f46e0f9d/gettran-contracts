import "@contracts/common/comments/messages"
import "deposits"
import "enums"

struct NftDelivery {
    recipient: address
    comment: Cell<TextComment>? = null
    queryId: uint64
    sponsor: address? = null
    hasReceipt: bool = false
    automaticAttempts: uint8 = 0
    // Точная выделенная сумма, а не текущая цена retry: сетевые тарифы могут измениться.
    automaticReserve: coins = 0
    status: NftDeliveryStatus = NftDeliveryStatus.Pending
}

type NftDeliveries = map<address, NftDelivery>

fun NftDeliveries.containsAny(self, items: ItemDeposits): bool {
    var entry = items.findFirst();
    while (entry.isFound) {
        if (self.exists(entry.getKey())) {
            return true;
        }
        entry = items.iterateNext(entry);
    }
    return false;
}

// Вся глобальная сумма состоит из помеченных обязательств. Чужую аллокацию нельзя
// освобождать через reconstructed/unexpected delivery с нулевым собственным резервом.
enum NftDeliveryReserveErrors {
    AllocationMismatch = 4601
}

fun NftDelivery.releaseAutomaticReserve(mutate self, mutate total: coins) {
    assert (total >= self.automaticReserve) throw NftDeliveryReserveErrors.AllocationMismatch;
    total -= self.automaticReserve;
    self.automaticReserve = 0;
}

fun NftDelivery.consumeAutomaticReserve(mutate self, mutate total: coins, amount: coins) {
    assert (
        amount > 0 && self.automaticReserve >= amount && total >= amount
    ) throw NftDeliveryReserveErrors.AllocationMismatch;
    self.automaticReserve -= amount;
    total -= amount;
}
