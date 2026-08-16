import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';

/**
 * GİRİŞ SAYFASI
 *
 * REAKTİF FORMLAR (Reactive Forms) NEDİR?
 * Formun yapısını ve kurallarını HTML'de değil, TypeScript sınıfında tanımlarız.
 * Avantajı: kurallar tek yerde toplanır, test edilebilir ve dinamik olarak
 * değiştirilebilir. (Alternatifi olan Template-Driven Forms'ta kurallar HTML
 * içine dağılır ve büyük formlarda kontrolü zorlaşır.)
 */
@Component({
  selector: 'app-login',
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './login.html',
  styleUrl: './login.css'
})
export class LoginComponent {
  private readonly fb = inject(FormBuilder);
  private readonly authService = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  /**
   * Şablonun (HTML) izlediği durumlar.
   * signal kullanıyoruz çünkü Angular 21 zoneless çalışır: değişikliğin
   * ekrana yansıması için Angular'ın bunu kesin olarak bilmesi gerekir.
   */
  readonly hataMesaji = signal<string | null>(null);
  readonly yukleniyor = signal(false);

  /** Interceptor 401 aldığında ?expired=true ile buraya yönlendirir. */
  readonly oturumDoldu = signal(this.route.snapshot.queryParamMap.get('expired') === 'true');

  /**
   * FORMUN TANIMI
   * Her alan: [başlangıç değeri, [doğrulama kuralları]]
   * nonNullable: true -> form.reset() yapıldığında alan null değil '' olur.
   */
  readonly form = this.fb.nonNullable.group({
    loginInput: ['', [Validators.required, Validators.minLength(3)]],
    password: ['', [Validators.required]]
  });

  // Şablonda form.controls.loginInput yerine kısa isim kullanmak için:
  get loginInput() {
    return this.form.controls.loginInput;
  }

  get password() {
    return this.form.controls.password;
  }

  gonder(): void {
    // Form geçersizse: tüm alanları "dokunulmuş" işaretle ki hata mesajları görünsün.
    // (Kullanıcı hiç tıklamadan Enter'a basarsa alanlar 'untouched' kalır ve
    //  hatalar gizli kalırdı; kullanıcı da neden gönderilmediğini anlamazdı.)
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.yukleniyor.set(true);
    this.hataMesaji.set(null);
    this.oturumDoldu.set(false);

    this.authService.login(this.form.getRawValue()).subscribe({
      next: () => {
        // Guard tarafından buraya yönlendirildiysek, kullanıcıyı asıl gitmek
        // istediği sayfaya geri götür. Yoksa dashboard'a.
        const returnUrl = this.route.snapshot.queryParamMap.get('returnUrl') ?? '/dashboard';
        this.router.navigateByUrl(returnUrl);
      },
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);
        this.hataMesaji.set(this.hatayiCozumle(hata));
      }
    });
  }

  /** HttpErrorResponse'u kullanıcının anlayacağı bir cümleye çevirir. */
  private hatayiCozumle(hata: HttpErrorResponse): string {
    // status 0: sunucuya HİÇ ulaşılamadı (API kapalı ya da CORS engeli).
    // Bu ayrımı yapmak, geliştirirken en çok vakit kazandıran şeydir.
    if (hata.status === 0) {
      return 'Sunucuya ulaşılamıyor. API çalışıyor mu? (http://localhost:5080)';
    }

    // Backend hataları { "message": "..." } biçiminde döndürüyor.
    return hata.error?.message ?? 'Giriş yapılamadı. Lütfen tekrar deneyin.';
  }
}
