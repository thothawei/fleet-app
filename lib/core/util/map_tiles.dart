/// OpenStreetMap 圖磚設定（乘客端地圖共用）。
///
/// 與 line-fleet-admin 後台同一圖磚來源，三端視覺一致、免任何 API key。
/// 開發／測試量在 OSM 使用政策內；正式上線量大時可改指向自架或 OpenFreeMap，
/// 只需換 [osmTileUrl] 一處。
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// OSM 要求標明送出請求的 App（避免被視為濫用而封鎖）。
const osmUserAgent = 'dev.linefleet.line_fleet_app';
