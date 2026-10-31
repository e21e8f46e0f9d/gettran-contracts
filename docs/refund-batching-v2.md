# Продукт v1: внутренний code profile 2, единая сдача и независимый claim

Публичная версия продукта остаётся **v1 / 1.0.0**. `profile 2` и compiled metadata `2.0.0` обозначают
внутреннюю несовместимую code/storage identity, а не второй продуктовый релиз.

Код **не активирован в production**. Новые `OfferEscrow` и `CertifiedOfferEscrow` имеют другие code hashes и несовместимую с v1 запись `NftDelivery`. Действующие immutable v1 остаются v1: подмена `MAINNET_*_V1` новым BOC запрещена.

## Поведение

На обычном завершении/отмене escrow не возвращает сдачу между NFT-подтверждениями. Последний подтверждённый delivery fence запускает один `Gas refund` фиксированному получателю. Settlement без NFT возвращает сдачу сразу. Principal, marketplace fee, NFT recipient и проверки подписи не менялись.

Если один NFT не отвечает, уже свободный остаток доступен через `ClaimEscrowSurplus`. Это независимый вывод сдачи, который не отмечает NFT доставленным и не отменяет его recovery. Плательщик — тот же бенефициар; сервисный кошелёк не участвует. Claim не имеет таймера и не запускается сам.

- Opcode: `0x434c5350` (`CLSP`). Body после opcode: `queryId:uint64`. Поля получателя нет.
- Доступ: только `Settled`, `Cancelled` или `Expired`; `in.senderAddress` должен совпадать с canonical reserve/excess beneficiary. Открытые и промежуточные payout-состояния запрещены.
- `surplus_claim()` возвращает `EscrowSurplusClaimInfo { beneficiary, available, minimumMessageValue }`.
- `minimumMessageValue` — аванс на bounded 120000 gas и один outgoing message по текущему тарифу. Неиспользованный аванс возвращается; это **не фиксированная комиссия**.
- Защищаются storage floor, точный `automaticRecoveryBudget` и все обязательства, допускающие закрытый status. Native principal/fee к закрытию уже поставлены в обязательные action messages; USDT principal находится в отдельных vault, storage/recovery reserve parent не выводится.
- Нулевой свободный остаток отклоняется с `4503`. Даже маленький положительный остаток технически доступен: UI обязан показать оценку расходов и не спамить автоматическими невыгодными запросами.
- Wallet message должен быть bounceable: если последний ACK успел вернуть сдачу раньше подписанного claim, отказ `4503` возвращает аванс caller за вычетом его газа.
- `queryId` служит корреляции, а не дебету зафиксированной суммы. Повтор не может вывести больше текущей свободной сдачи; stale/repeated calls не обнуляют защищённый резерв.

### Sponsor/recovery

В recovery-случае возможны дополнительные сообщения: остаток чужого caller-funded retry возвращается **этому спонсору**, свободная общая сдача — фиксированному бенефициару. Объединять разные права на один адрес нельзя. После частичного claim и позднего разрешения зависшего NFT может появиться второй возврат: один перевод — цель обычного сценария, не обещание для всех failure paths.

## Точный учёт automatic reserve

В v2 `NftDelivery` содержит `automaticReserve:coins` между `automaticAttempts:uint8` и `status:uint8`. Ноль означает, что именно этой записи бюджет не выделялся. Сумма записей равна `automaticRecoveryBudget`.

1. Начальная отправка/возврат реально депонированного NFT получает точную аллокацию по текущему тарифу.
2. Manual sponsor retry сохраняет её. Unexpected/reconstructed delivery не получает чужой резерв.
3. Automatic retry тратит только собственную аллокацию и уменьшает глобальную сумму ровно на расход. При повышении тарифа сверх собственной аллокации остаётся caller-funded путь; нельзя занимать у другого NFT.
4. Подтверждённое либо уже существующее recipient-authorized ручное завершение освобождает **сохранённую сумму**, а не новую сетевую цену. Повторные/неподходящие ACK не освобождают её дважды.

`coins`, а не флаг, нужен из-за изменения сетевых тарифов между выделением и возвратом бюджета. Запись v1 не содержит этого поля. Ни старый parser, ни старый code registry нельзя считать совместимыми с v2.

## Проверки и генерация

Acton 1.2.1, только локальное выполнение:

```sh
acton build
acton test tests/refund_batching --no-capture
acton check
acton fmt --check
```

`tests/refund_batching/fixtures/*v1.boc` — замороженные BOC исходного reviewed-by-code-hash runtime для сравнительного теста. Baseline Certified hash `E20E35D0557D3A98A520832262C9B5565E9B4A2CCAC07F6549531E578995462B` совпал с наблюдавшимся on-chain адресом.

Локальная регенерация protocol fixtures:

```sh
acton script scripts/export_refund_protocol.tolk
```

Скрипт явно отвергает broadcasting. Golden fixtures включают claim body, новую delivery-запись и реальные локальные settled-state cells обоих runtime. Не использовать `--net`.

Покрываются все порядки трёх ACK, stale/duplicate ACK, нет NFT, exact fast-sale/fast-purchase, native principal/fees, cancel, foreign/underfunded/nonclosed claim, один неответивший NFT, повторный и partial claim, sponsored/manual/automatic recovery, unexpected/reconstructed delivery, повышение/снижение gas price, USDT storage и нагрузка 100 NFT +32 assigned USDT records. После локальных шагов проверяется сумма аллокаций. Старый и новый runtime сравниваются в одной конфигурации, а не по разным скриншотам.

## До выпуска остаётся

Backend codec/code-registry/claim-builder/UX уже поддерживают оба immutable профиля. Отдельный
readiness patch разрешает явный выбор profile 2 для создания; default остаётся 1 до reviewed release.
Актуальный isolated run: 51 исходный TVM сценарий плюс 2 backend-generated initial-data/адрес/getter
interop сценария. Это не on-chain wallet/lifecycle E2E. Для активации остаются review финансовых
инвариантов и точного профиля, явный testnet wallet/lifecycle gate, затем отдельный release. Native network profile здесь mainnet; локальная эмуляция не является mainnet-деплоем. На старых escrow новый claim отсутствует. Любая активация/смена deployment version — отдельный проверяемый выпуск.
