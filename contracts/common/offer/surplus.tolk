import "@contracts/common/gas/costs"
import "@contracts/common/gas/types"
import "@contracts/common/nft/deliveries"
import "@contracts/common/ton/transfers"

enum EscrowSurplusClaimErrors {
    NotBeneficiary = 4501
    NotEnoughValue = 4502
    NoClaimableSurplus = 4503
}

// Caller оплачивает весь bounded claim, включая USDT storage-size projection; остаток его
// сообщения возвращается тому же beneficiary. Нельзя субсидировать claim защищённым recovery.
const GAS_ESCROW_SURPLUS_CLAIM = GasUnits { value: 120_000 }

fun requiredEscrowSurplusClaimValue(): coins {
    return executionCost(GAS_ESCROW_SURPLUS_CLAIM, 1);
}

fun claimEscrowSurplus(
    sender: address,
    msgValue: coins,
    beneficiary: address,
    protectedBalance: coins,
) {
    assert (sender == beneficiary) throw EscrowSurplusClaimErrors.NotBeneficiary;
    val required = requiredEscrowSurplusClaimValue();
    assert (msgValue >= required) throw EscrowSurplusClaimErrors.NotEnoughValue;
    // Новый взнос caller не считается старой сдачей. Даже маленький остаток доступен
    // бенефициару: оценить выгодность вывода обязан UI, а не блокирующий средства порог.
    val previousSurplus = claimableEscrowSurplus(protectedBalance, msgValue);
    assert (previousSurplus > 0) throw EscrowSurplusClaimErrors.NoClaimableSurplus;
    returnChange(beneficiary, protectedBalance);
}

struct EscrowSurplusClaimInfo {
    beneficiary: address
    available: coins
    minimumMessageValue: coins
}

fun claimableEscrowSurplus(protectedBalance: coins, msgValue: coins = 0): coins {
    return max(0, contract.getOriginalBalance() - msgValue - protectedBalance) as coins;
}

// Состояние closed — доменный факт, а не настройка режима отправки. Проверка до
// дорогой USDT storage projection сохраняет экономию на промежуточных NFT ACK.
fun mayReturnEscrowChange(isClosed: bool, deliveries: NftDeliveries): bool {
    return !isClosed || deliveries.isEmpty();
}
