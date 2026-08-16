import { provideHttpClient } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { App } from './app';
import { routes } from './app.routes';

/**
 * Kök bileşenin ayağa kalkabildiğini doğrulayan temel test.
 *
 * App artık <router-outlet /> içerdiği için testte Router'ın sağlanması gerekir;
 * yoksa "No provider for Router" hatası alınır. HttpClient'ı da sağlıyoruz çünkü
 * rota ağacındaki bileşenler AuthService üzerinden ona bağımlı.
 */
describe('App', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [provideRouter(routes), provideHttpClient()]
    }).compileComponents();
  });

  it('bileşen oluşturulabilmeli', () => {
    const fixture = TestBed.createComponent(App);
    expect(fixture.componentInstance).toBeTruthy();
  });

  it('router-outlet render edilmeli', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector('router-outlet')).toBeTruthy();
  });
});
