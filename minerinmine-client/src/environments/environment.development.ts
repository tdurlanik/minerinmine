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
  apiUrl: 'http://localhost:5080/api'
};
