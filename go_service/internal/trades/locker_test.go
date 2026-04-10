package trades

// Compile-time interface compliance check.
var _ InventoryLocker = (*DBInventoryLocker)(nil)
