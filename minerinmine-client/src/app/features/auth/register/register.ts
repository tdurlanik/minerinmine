import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import {
  AbstractControl,
  FormBuilder,
  ReactiveFormsModule,
  ValidationErrors,
  Validators
} from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';

/**
 * ÖZEL DOĞRULAYICI (Custom Validator) — Şifre Eşleşme Kontrolü
 *
 * NEDEN AYRI BİR FONKSİYON?
 * Validators.required gibi hazır kurallar TEK BİR ALANA bakar. Ama "şifre ile
 * şifre tekrarı aynı mı?" sorusu İKİ ALANI birden karşılaştırmayı gerektirir.
 * Bu tür kurallara "cross-field validation" denir ve tek bir alana değil,
 * onları KAPSAYAN FormGroup'a bağlanır.
 *
 * Dönüş değeri sözleşmesi:
 *   null döndür        -> geçerli
 *   { hataAdi: true }  -> geçersiz (bu nesne control.errors içine yazılır)
 */
export function sifreEslesmeValidator(group: AbstractControl): ValidationErrors | null {
  const sifre = group.get('password')?.value;
  const sifreTekrar = group.get('confirmPassword')?.value;

  // Kullanıcı henüz tekrar alanına yazmaya başlamadıysa hata gösterme.
  // Yoksa form açılır açılmaz "şifreler eşleşmiyor" yazardı — rahatsız edici olurdu.
  if (!sifreTekrar) {
    return null;
  }

  return sifre === sifreTekrar ? null : { sifreEslesmiyor: true };
}

/**
 * KAYIT SAYFASI
 */
@Component({
  selector: 'app-register',
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './register.html',
  styleUrl: './register.css'
})
export class RegisterComponent {
  private readonly fb = inject(FormBuilder);
  private readonly authService = inject(AuthService);
  private readonly router = inject(Router);

  readonly hataMesaji = signal<string | null>(null);
  readonly yukleniyor = signal(false);

  /**
   * Form tanımı.
   * İkinci parametre (validators) FormGroup SEVİYESİNDE çalışan kuralları alır.
   * Şifre eşleşme kontrolünü buraya bağlıyoruz çünkü iki alanı birden görmesi gerekiyor.
   */
  readonly form = this.fb.nonNullable.group(
    {
      username: ['', [Validators.required, Validators.minLength(3), Validators.maxLength(50)]],
      email: ['', [Validators.required, Validators.email]],
      password: ['', [Validators.required, Validators.minLength(6)]],
      confirmPassword: ['', [Validators.required]]
    },
    { validators: sifreEslesmeValidator }
  );

  get username() {
    return this.form.controls.username;
  }

  get email() {
    return this.form.controls.email;
  }

  get password() {
    return this.form.controls.password;
  }

  get confirmPassword() {
    return this.form.controls.confirmPassword;
  }

  /** Şifreler eşleşmiyor hatası gösterilmeli mi? */
  get sifreEslesmiyor(): boolean {
    return this.form.hasError('sifreEslesmiyor') && this.confirmPassword.touched;
  }

  gonder(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.yukleniyor.set(true);
    this.hataMesaji.set(null);

    // DİKKAT: confirmPassword'ü API'ye GÖNDERMİYORUZ.
    // O alan sadece kullanıcının yazım hatası yapmasını engellemek için vardır;
    // sunucunun onunla hiçbir işi yoktur. Backend'in RegisterRequest DTO'sunda
    // böyle bir alan da yok — gönderirsek yok sayılırdı, ama göndermemek daha temiz.
    const { username, email, password } = this.form.getRawValue();

    this.authService.register({ username, email, password }).subscribe({
      next: () => {
        // Backend kayıt sonrası otomatik giriş yaptırıp token döndürüyor,
        // bu yüzden kullanıcıyı login'e değil doğrudan dashboard'a alıyoruz.
        this.router.navigateByUrl('/dashboard');
      },
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);
        this.hataMesaji.set(this.hatayiCozumle(hata));
      }
    });
  }

  private hatayiCozumle(hata: HttpErrorResponse): string {
    if (hata.status === 0) {
      return 'Sunucuya ulaşılamıyor. API çalışıyor mu? (http://localhost:5080)';
    }

    // Backend'in kendi mesajı ("Bu kullanıcı adı zaten kullanılmaktadır.")
    if (hata.error?.message) {
      return hata.error.message;
    }

    // [ApiController] DTO doğrulaması patlarsa ASP.NET, RFC 7807 biçiminde
    // { errors: { Alan: ["mesaj"] } } döndürür. İlk mesajı çıkarıp gösteriyoruz.
    if (hata.error?.errors) {
      const ilkHata = Object.values(hata.error.errors as Record<string, string[]>)[0];
      if (ilkHata?.length) {
        return ilkHata[0];
      }
    }

    return 'Kayıt yapılamadı. Lütfen tekrar deneyin.';
  }
}
