/**
 * Geliştirme (development) ortamı ayarları.
 * `ng serve` çalıştırıldığında Angular bu dosyayı environment.ts'in YERİNE koyar
 * (angular.json içindeki "fileReplacements" ayarı sayesinde).
 *
 * NEDEN BÖYLE?
 * Kod içinde 'http://localhost:5080' gibi adresleri elle yazmayız. Adres tek bir
 * yerde tanımlanır; ortam değiştiğinde kod değil sadece bu dosya değişir.
 *
 * apiUrl, .NET API'sinin launchSettings.json'da sabitlediğimiz HTTP portudur (5080).
 */
export const environment = {
  production: false,
  apiUrl: 'http://localhost:5080/api',

  /**
   * SignalR hub adresi.
   *
   * apiUrl'den ayri tutuluyor cunku hub'lar /api altinda degil: bunlar
   * controller degil, ayri bir uc turu. Sunucuda "/hubs/chat" olarak
   * haritalandi (Program.cs -> app.MapHub).
   */
  hubUrl: 'http://localhost:5080/hubs'
};
