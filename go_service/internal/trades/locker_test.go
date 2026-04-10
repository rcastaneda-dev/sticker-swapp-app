package trades

// Compile-time interface compliance checks.
var _ InventoryLocker = (*DBInventoryLocker)(nil)
var _ TradeExecutor = (*DBTradeExecutor)(nil)
