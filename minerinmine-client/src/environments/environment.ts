/**
 * Üretim (production) ortamı ayarları.
 * `ng build` çalıştırıldığında bu dosya kullanılır — Docker imajı da bunu kullanır.
 *
 * NEDEN TAM ADRES DEĞİL DE '/api'?
 * Geliştirmede tarayıcı 4200'de, API 5080'deydi: farklı origin. Bu yüzden
 * tam adres ('http://localhost:5080/api') yazmak ve CORS ayarlamak gerekiyordu.
 *
 * Docker'da ise tarayıcı için TEK bir adres var (8080): hem sayfalar hem /api
 * oradan geliyor. nginx, /api ile başlayan istekleri API container'ına
 * iletiyor. Adres göreli olduğu için:
 *   - CORS sorunu ortadan kalkar (aynı origin)
 *   - HttpOnly refresh cookie'si ek ayar gerektirmeden çalışır
 *   - Uygulama hangi makinede yayınlanırsa yayınlansın adres doğru kalır
 */
export const environment = {
  production: true,
  apiUrl: '/api'
};
