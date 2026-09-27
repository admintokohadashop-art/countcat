# TikTokSeller

A lightweight, offline-first Flutter foundation for recording TikTok Seller sales recaps on Android and Windows.

## Foundation scope

This milestone supplies a Material 3 app shell, responsive navigation, five placeholder feature pages, and a versioned SQLite schema. It intentionally does not include sale entry, session management, reports, search, editing, calculations, or synchronization.

## Dependencies

- `sqflite` provides the mature SQLite API used on Android.
- `sqflite_common_ffi` provides the SQLite FFI factory used on Windows.

No state-management, networking, cloud, authentication, or backend packages are included.

## Database design

`AppDatabase` creates three tables: `settings`, `live_sessions`, and `transactions`. The schema keeps `payment_status` and `order_status` as separate constrained columns. `transactions.id` is the internal primary key and `order_id` is unique to support future duplicate detection. Money is stored as integer minor currency units, avoiding floating-point rounding issues.

Database initialization is the only platform-aware point: Android uses `sqflite`; Windows uses `sqflite_common_ffi`. The rest of the application uses the same Dart database interface.
