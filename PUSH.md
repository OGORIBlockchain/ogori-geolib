# Đẩy repo lên GitHub

Repo `https://github.com/OGORIBlockchain/ogori-geolib` đã tồn tại và trống. Thư mục này đã đóng gói xong, chỉ cần đẩy lên.

Tôi không đẩy hộ được: `gh` của bạn xác thực trên máy bạn, còn tôi chạy trong môi trường cách ly không có (và không nên có) thông tin đăng nhập của bạn.

## Chạy trên máy bạn

Mở PowerShell tại `C:\Users\NDQUAN\Desktop\BaoCaoKhoaHoc\ogori-geolib`:

```powershell
git init -b main
git add .
git commit -m "On-chain point-in-polygon verification and versioned audit lenses

Research artefact for two manuscripts on field-evidence verification in
agri-food traceability. Contracts, gas benchmark, client-side timing, and the
production field data used for cross-validation."
git remote add origin https://github.com/OGORIBlockchain/ogori-geolib.git
git push -u origin main
```

`.gitignore` đã loại `node_modules/`, `artifacts/`, `cache/` nên lần đẩy đầu chỉ khoảng vài trăm KB.

## Kiểm tra sau khi đẩy

```powershell
gh repo view OGORIBlockchain/ogori-geolib --web
```

Cần thấy: `contracts/` có 3 file, `test/` có 3 file, `data/` có 4 file, README hiển thị bảng gas và bảng kiểm chứng.

## Gắn DOI cho bài báo (khuyến nghị)

Tạp chí thích trích dẫn mã nguồn có DOI cố định hơn là link GitHub, vì GitHub có thể đổi. Cách làm miễn phí:

1. Đăng nhập https://zenodo.org bằng tài khoản GitHub
2. Vào Settings → GitHub, bật công tắc cho `OGORIBlockchain/ogori-geolib`
3. Trên GitHub tạo một release, đặt tag `v1.0.0`
4. Zenodo tự sinh DOI. Lấy DOI đó thay cho link GitHub trong mục Data availability của cả hai bản thảo

Nói tôi biết DOI khi có, tôi thay vào bốn file bản thảo.

## Nội dung repo

| Đường dẫn | Nội dung |
|---|---|
| `contracts/GeoLib.sol` | Hình học cầu dấu phẩy tĩnh: haversine, ray-casting, khoảng cách điểm-đoạn |
| `contracts/LandRegistry.sol` | Đa giác thửa ghi-một-lần, ngưỡng theo thửa, xác minh trong giao dịch |
| `contracts/LensRegistry.sol` | Neo digest rule-set, chỉ ghi log |
| `test/benchmark.js` | Đo gas + đối chiếu với 44 sự kiện production |
| `test/latency_client.mjs` | Đo chi phí tái đánh giá phía client bằng Node |
| `test/latency_client.html` | Bản chạy trong trình duyệt, mở lên bấm nút |
| `data/` | Đa giác 3 thửa, 44 sự kiện, kết quả benchmark, ma trận cross-lens |
