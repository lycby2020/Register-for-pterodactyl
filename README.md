# Register-for-pterodactyl
# 📘 Instalación Manual - Sistema de Registro para Pterodactyl v1.12.0

## 📋 Requisitos Previos

- Pterodactyl Panel v1.12.0 instalado y funcionando
- Acceso SSH con privilegios root o sudo
- Editor de texto (nano, vim, etc.)

---

## 🗂️ Estructura de Archivos del Addon

```
/var/www/pterodactyl/
│
├── app/
│   └── Http/
│       └── Controllers/
│           └── Auth/
│               └── RegisterController.php          [NUEVO]
│
├── resources/
│   ├── views/
│   │   ├── auth/
│   │   │   ├── register.blade.php                 [NUEVO]
│   │   │   └── login.blade.php                    [MODIFICAR]
│   │   └── emails/
│   │       └── welcome.blade.php                  [NUEVO]
│
├── routes/
│   └── auth.php                                    [MODIFICAR]
│
├── config/
│   └── pterodactyl.php                            [MODIFICAR]
│
├── .env                                            [MODIFICAR]
│
├── LICENSE                                         [NUEVO - OPCIONAL]
└── REGISTER_ADDON_README.md                       [NUEVO - OPCIONAL]
```

---

## 🔧 Instalación Paso a Paso

### **PASO 1: Crear Backup de Seguridad**

```bash
# Crear directorio de backup
mkdir -p /var/www/pterodactyl/backups/manual-install-$(date +%Y%m%d)

# Hacer backup de archivos que modificaremos
cp /var/www/pterodactyl/routes/auth.php /var/www/pterodactyl/backups/manual-install-$(date +%Y%m%d)/
cp /var/www/pterodactyl/config/pterodactyl.php /var/www/pterodactyl/backups/manual-install-$(date +%Y%m%d)/
cp /var/www/pterodactyl/.env /var/www/pterodactyl/backups/manual-install-$(date +%Y%m%d)/

echo "✓ Backup creado exitosamente"
```

---

### **PASO 2: Crear el Controlador de Registro**

```bash
# Crear directorio si no existe
mkdir -p /var/www/pterodactyl/app/Http/Controllers/Auth

# Crear archivo
nano /var/www/pterodactyl/app/Http/Controllers/Auth/RegisterController.php
```

**Contenido completo del archivo:**

```php
<?php

namespace Pterodactyl\Http\Controllers\Auth;

use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Foundation\Auth\RegistersUsers;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Illuminate\Auth\Events\Registered;
use Pterodactyl\Exceptions\DisplayException;

class RegisterController extends Controller
{
    use RegistersUsers;

    protected $redirectTo = '/';

    public function __construct()
    {
        $this->middleware('guest');
    }

    /**
     * Muestra el formulario de registro
     */
    public function showRegistrationForm()
    {
        if (!config('pterodactyl.auth.registration_enabled', true)) {
            throw new DisplayException('El registro de usuarios está deshabilitado.');
        }

        return view('auth.register');
    }

    /**
     * Valida los datos del registro
     */
    protected function validator(array $data)
    {
        $rules = [
            'username' => [
                'required',
                'string',
                'min:3',
                'max:255',
                'unique:users,username',
                'regex:/^[a-zA-Z0-9_\-]+$/'
            ],
            'email' => [
                'required',
                'string',
                'email',
                'max:255',
                'unique:users,email'
            ],
            'password' => [
                'required',
                'string',
                'min:8',
                'confirmed',
                'regex:/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$/'
            ],
            'name_first' => ['required', 'string', 'max:255'],
            'name_last' => ['required', 'string', 'max:255'],
        ];

        $messages = [
            'username.regex' => 'El nombre de usuario solo puede contener letras, números, guiones y guiones bajos.',
            'username.unique' => 'Este nombre de usuario ya está en uso.',
            'username.min' => 'El nombre de usuario debe tener al menos 3 caracteres.',
            'email.unique' => 'Este correo electrónico ya está registrado.',
            'email.email' => 'Ingresa un correo electrónico válido.',
            'password.min' => 'La contraseña debe tener al menos 8 caracteres.',
            'password.confirmed' => 'Las contraseñas no coinciden.',
            'password.regex' => 'La contraseña debe contener al menos una mayúscula, una minúscula y un número.',
            'name_first.required' => 'El nombre es requerido.',
            'name_last.required' => 'El apellido es requerido.',
        ];

        return Validator::make($data, $rules, $messages);
    }

    /**
     * Crea un nuevo usuario
     */
    protected function create(array $data)
    {
        $user = User::forceCreate([
            'uuid' => Str::uuid()->toString(),
            'username' => $data['username'],
            'email' => $data['email'],
            'name_first' => $data['name_first'],
            'name_last' => $data['name_last'],
            'password' => Hash::make($data['password']),
            'root_admin' => false,
            'language' => config('app.locale', 'en'),
        ]);

        // Enviar email de bienvenida (si está configurado)
        if (config('mail.driver') !== 'array') {
            try {
                Mail::send('emails.welcome', ['user' => $user], function ($message) use ($user) {
                    $message->to($user->email, $user->name_first . ' ' . $user->name_last)
                            ->subject('¡Bienvenido a ' . config('app.name') . '!');
                });
            } catch (\Exception $e) {
                \Log::warning('No se pudo enviar email de bienvenida: ' . $e->getMessage());
            }
        }

        return $user;
    }

    /**
     * Maneja el registro de un usuario
     */
    public function register(Request $request)
    {
        if (!config('pterodactyl.auth.registration_enabled', true)) {
            return redirect()->route('auth.login')
                ->with('error', 'El registro de usuarios está deshabilitado.');
        }

        $this->validator($request->all())->validate();

        event(new Registered($user = $this->create($request->all())));

        $this->guard()->login($user);

        return $this->registered($request, $user)
                        ?: redirect($this->redirectPath())
                            ->with('success', '¡Cuenta creada exitosamente! Bienvenido.');
    }
}
```

**Guardar:** `CTRL + O`, luego `ENTER`, después `CTRL + X`

---

### **PASO 3: Crear Vista de Registro**

```bash
# Crear archivo de vista
nano /var/www/pterodactyl/resources/views/auth/register.blade.php
```

**Contenido completo:**

```blade
@extends('layouts.auth')

@section('title')
    Registro
@endsection

@section('content')
<div class="w-full max-w-md">
    <div class="bg-white dark:bg-gray-800 shadow-md rounded-lg px-8 pt-6 pb-8 mb-4">
        <div class="text-center mb-6">
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
                Crear cuenta
            </h1>
            <p class="text-sm text-gray-600 dark:text-gray-400 mt-2">
                Regístrate para acceder al panel
            </p>
        </div>

        @if(session('error'))
            <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative mb-4" role="alert">
                <span class="block sm:inline">{{ session('error') }}</span>
            </div>
        @endif

        <form method="POST" action="{{ route('auth.register') }}">
            @csrf

            {{-- Nombre y Apellido --}}
            <div class="flex gap-4 mb-4">
                <div class="flex-1">
                    <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2" for="name_first">
                        Nombre
                    </label>
                    <input 
                        class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline @error('name_first') border-red-500 @enderror" 
                        id="name_first" 
                        name="name_first" 
                        type="text" 
                        value="{{ old('name_first') }}"
                        placeholder="Tu nombre" 
                        required 
                        autofocus
                    >
                    @error('name_first')
                        <p class="text-red-500 text-xs italic mt-1">{{ $message }}</p>
                    @enderror
                </div>

                <div class="flex-1">
                    <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2" for="name_last">
                        Apellido
                    </label>
                    <input 
                        class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline @error('name_last') border-red-500 @enderror" 
                        id="name_last" 
                        name="name_last" 
                        type="text" 
                        value="{{ old('name_last') }}"
                        placeholder="Tu apellido" 
                        required
                    >
                    @error('name_last')
                        <p class="text-red-500 text-xs italic mt-1">{{ $message }}</p>
                    @enderror
                </div>
            </div>

            {{-- Username --}}
            <div class="mb-4">
                <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2" for="username">
                    Nombre de usuario
                </label>
                <input 
                    class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline @error('username') border-red-500 @enderror" 
                    id="username" 
                    name="username" 
                    type="text" 
                    value="{{ old('username') }}"
                    placeholder="usuario123" 
                    required
                >
                @error('username')
                    <p class="text-red-500 text-xs italic mt-1">{{ $message }}</p>
                @enderror
            </div>

            {{-- Email --}}
            <div class="mb-4">
                <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2" for="email">
                    Correo electrónico
                </label>
                <input 
                    class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline @error('email') border-red-500 @enderror" 
                    id="email" 
                    name="email" 
                    type="email" 
                    value="{{ old('email') }}"
                    placeholder="tu@email.com" 
                    required
                >
                @error('email')
                    <p class="text-red-500 text-xs italic mt-1">{{ $message }}</p>
                @enderror
            </div>

            {{-- Password --}}
            <div class="mb-4">
                <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2" for="password">
                    Contraseña
                </label>
                <input 
                    class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 mb-1 leading-tight focus:outline-none focus:shadow-outline @error('password') border-red-500 @enderror" 
                    id="password" 
                    name="password" 
                    type="password" 
                    placeholder="••••••••" 
                    required
                >
                <p class="text-xs text-gray-500 dark:text-gray-400">Mínimo 8 caracteres, incluye mayúsculas, minúsculas y números</p>
                @error('password')
                    <p class="text-red-500 text-xs italic mt-1">{{ $message }}</p>
                @enderror
            </div>

            {{-- Password Confirmation --}}
            <div class="mb-6">
                <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2" for="password_confirmation">
                    Confirmar contraseña
                </label>
                <input 
                    class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline" 
                    id="password_confirmation" 
                    name="password_confirmation" 
                    type="password" 
                    placeholder="••••••••" 
                    required
                >
            </div>

            {{-- Submit Button --}}
            <div class="mb-6">
                <button 
                    class="w-full bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline transition duration-150" 
                    type="submit"
                >
                    Crear cuenta
                </button>
            </div>

            {{-- Login Link --}}
            <div class="text-center">
                <a class="inline-block align-baseline font-bold text-sm text-blue-500 hover:text-blue-800 dark:hover:text-blue-400" 
                   href="{{ route('auth.login') }}">
                    ¿Ya tienes cuenta? Inicia sesión
                </a>
            </div>
        </form>
    </div>
</div>
@endsection
```

**Guardar:** `CTRL + O` → `ENTER` → `CTRL + X`

---

### **PASO 4: Crear Template de Email de Bienvenida**

```bash
# Crear directorio si no existe
mkdir -p /var/www/pterodactyl/resources/views/emails

# Crear archivo
nano /var/www/pterodactyl/resources/views/emails/welcome.blade.php
```

**Contenido:**

```blade
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bienvenido</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background-color: #f4f4f4;
            margin: 0;
            padding: 0;
        }
        .container {
            max-width: 600px;
            margin: 20px auto;
            background: #ffffff;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px 20px;
            text-align: center;
        }
        .content {
            padding: 30px 20px;
        }
        .button {
            display: inline-block;
            padding: 12px 30px;
            background: #667eea;
            color: white;
            text-decoration: none;
            border-radius: 5px;
            margin: 20px 0;
        }
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            font-size: 12px;
            color: #666;
        }
        .info-box {
            background: #f8f9fa;
            border-left: 4px solid #667eea;
            padding: 15px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1 style="margin: 0; font-size: 28px;">¡Bienvenido a {{ config('app.name') }}!</h1>
        </div>
        
        <div class="content">
            <p>Hola <strong>{{ $user->name_first }}</strong>,</p>
            
            <p>Tu cuenta ha sido creada exitosamente. ¡Estamos emocionados de tenerte con nosotros!</p>
            
            <div class="info-box">
                <p style="margin: 5px 0;"><strong>📧 Email:</strong> {{ $user->email }}</p>
                <p style="margin: 5px 0;"><strong>👤 Usuario:</strong> {{ $user->username }}</p>
            </div>
            
            <p>Ya puedes acceder al panel y comenzar a gestionar tus servicios.</p>
            
            <center>
                <a href="{{ route('index') }}" class="button">Acceder al Panel</a>
            </center>
            
            <p style="margin-top: 30px; font-size: 14px; color: #666;">
                Si tienes alguna pregunta o necesitas ayuda, no dudes en contactarnos.
            </p>
        </div>
        
        <div class="footer">
            <p>Este email fue enviado automáticamente. Por favor no respondas a este mensaje.</p>
            <p>&copy; {{ date('Y') }} {{ config('app.name') }}. Todos los derechos reservados.</p>
        </div>
    </div>
</body>
</html>
```

**Guardar:** `CTRL + O` → `ENTER` → `CTRL + X`

---

### **PASO 5: Agregar Rutas**

```bash
nano /var/www/pterodactyl/routes/auth.php
```

**Al final del archivo, agregar:**

```php

/*
|--------------------------------------------------------------------------
| Custom Registration Routes
|--------------------------------------------------------------------------
*/
Route::middleware('guest')->group(function () {
    Route::get('/register', 'Auth\RegisterController@showRegistrationForm')->name('auth.register');
    Route::post('/register', 'Auth\RegisterController@register');
});
```

**Guardar:** `CTRL + O` → `ENTER` → `CTRL + X`

---

### **PASO 6: Modificar Configuración**

```bash
nano /var/www/pterodactyl/config/pterodactyl.php
```

**Buscar la línea que dice `return [` (al inicio del archivo) y agregar después:**

```php
    // Configuración del sistema de registro
    'auth' => [
        'registration_enabled' => env('REGISTRATION_ENABLED', true),
    ],
```

**Debería verse así:**

```php
<?php

return [
    // Configuración del sistema de registro
    'auth' => [
        'registration_enabled' => env('REGISTRATION_ENABLED', true),
    ],

    // ... resto del contenido original ...
];
```

**Guardar:** `CTRL + O` → `ENTER` → `CTRL + X`

---

### **PASO 7: Agregar Variable de Entorno**

```bash
nano /var/www/pterodactyl/.env
```

**Al final del archivo, agregar:**

```env

# Sistema de Registro
REGISTRATION_ENABLED=true
```

**Guardar:** `CTRL + O` → `ENTER` → `CTRL + X`

---

### **PASO 8: Modificar Vista de Login (Agregar Link de Registro)**

```bash
nano /var/www/pterodactyl/resources/views/auth/login.blade.php
```

**Buscar el botón de "Iniciar sesión" (submit button) y agregar después de `</button>`:**

```blade
<div class="mt-6 text-center">
    <a href="{{ route('auth.register') }}" class="text-sm text-blue-500 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300">
        ¿No tienes cuenta? <strong>Regístrate aquí</strong>
    </a>
</div>
```

**Guardar:** `CTRL + O` → `ENTER` → `CTRL + X`

---

### **PASO 9: Establecer Permisos Correctos**

```bash
# Establecer propietario correcto
chown -R www-data:www-data /var/www/pterodactyl

# Establecer permisos de archivos
find /var/www/pterodactyl -type f -exec chmod 644 {} \;

# Establecer permisos de directorios
find /var/www/pterodactyl -type d -exec chmod 755 {} \;

# Permisos especiales para storage y cache
chmod -R 755 /var/www/pterodactyl/storage
chmod -R 755 /var/www/pterodactyl/bootstrap/cache
```

---

### **PASO 10: Limpiar y Cachear**

```bash
cd /var/www/pterodactyl

# Limpiar cache
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan route:clear

# Reconstruir cache (opcional pero recomendado)
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

---

## ✅ Verificación de Instalación

### **1. Verificar que las rutas existen:**

```bash
php artisan route:list | grep register
```

**Deberías ver:**

```
GET|HEAD   auth/register ............... auth.register › Auth\RegisterController@showRegistrationForm
POST       auth/register ..................... Auth\RegisterController@register
```

### **2. Verificar permisos:**

```bash
ls -la /var/www/pterodactyl/app/Http/Controllers/Auth/RegisterController.php
```

**Debería mostrar:** `www-data www-data` como propietario

### **3. Probar acceso:**

Abre tu navegador y ve a: `https://tu-panel.com/auth/register`

---

## 📝 Archivos Opcionales

### **LICENSE (Opcional)**

```bash
nano /var/www/pterodactyl/LICENSE-REGISTRATION-ADDON
```

```text
MIT License

Copyright (c) 2025 Pterodactyl Registration Addon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### **README (Opcional)**

```bash
nano /var/www/pterodactyl/REGISTRATION-ADDON-README.md
```

```markdown
# Pterodactyl User Registration Addon

Sistema completo de registro de usuarios para Pterodactyl Panel v1.12.0

## Características

- ✅ Formulario de registro moderno y responsive
- ✅ Validación completa de datos
- ✅ Emails de bienvenida automáticos
- ✅ Sistema de habilitación/deshabilitación
- ✅ Compatible con dark mode

## Configuración

### Habilitar/Deshabilitar
Edita `.env`:
```env
REGISTRATION_ENABLED=true
```

### Configurar Emails
```env
MAIL_DRIVER=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=tu@email.com
MAIL_PASSWORD=tu_password
MAIL_ENCRYPTION=tls
```

## Rutas
- Registro: `/auth/register`
- Login: `/auth/login`

## Soporte
Logs: `storage/logs/laravel.log`
```

---

## 🔧 Configuración de SMTP (Para Emails)

Si quieres que se envíen emails de bienvenida, edita `.env`:

```bash
nano /var/www/pterodactyl/.env
```

**Agrega o modifica:**

```env
# Configuración de Email
MAIL_DRIVER=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=tucorreo@gmail.com
MAIL_PASSWORD=tu_contraseña_de_aplicacion
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@tudominio.com
MAIL_FROM_NAME="${APP_NAME}"
```

**Para Gmail:**
1. Ve a tu cuenta de Google
2. Activa verificación en 2 pasos
3. Genera una "Contraseña de aplicación"
4. Usa esa contraseña en `MAIL_PASSWORD`

---

## 🐛 Solución de Problemas

### **Error 404 en /register**

```bash
php artisan route:clear
php artisan route:cache
php artisan config:clear
```

### **Página en blanco o error 500**

```bash
# Ver logs
tail -f /var/www/pterodactyl/storage/logs/laravel.log

# Verificar permisos
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl/storage
```

### **No se envían emails**

```bash
# Probar configuración SMTP
cd /var/www/pterodactyl
php artisan tinker

# En tinker, ejecutar:
Mail::raw('Test email', function($msg) { 
    $msg->to('tu@email.com')->subject('Prueba'); 
});
```

### **Error "Class RegisterController not found"**

```bash
# Regenerar autoload
composer dump-autoload

# Limpiar cache
php artisan clear-compiled
php artisan config:clear
```

---

## 🗑️ Desinstalación

```bash
# 1. Eliminar archivos
rm /var/www/pterodactyl/app/Http/Controllers/Auth/RegisterController.php
rm /var/www/pterodactyl/resources/views/auth/register.blade.php
rm /var/www/pterodactyl/resources/views/emails/welcome.blade.php

# 2. Editar routes/auth.php y eliminar las rutas de registro
nano /var/www/pterodactyl/routes/auth.php
# Elimina el bloque de rutas de registro

# 3. Editar config/pterodactyl.php
nano /var/www/pterodactyl/config/pterodactyl.php
# Elimina el bloque 'auth'

# 4. Editar .env
nano /var/www/pterodactyl/.env
# Elimina REGISTRATION_ENABLED=true

# 5. Limpiar cache
php artisan config:clear
php artisan route:clear
php artisan cache:clear

# 6. Restaurar backup si es necesario
# cp /var/www/pterodactyl/backups/[fecha]/auth.php /var/www/pterodactyl/routes/
```

---

## 📊 Checklist de Instalación

- [ ] Backup creado
- [ ] RegisterController.php creado
- [ ] register.blade.php creado
- [ ] welcome.blade.php creado
- [ ] Rutas agregadas en auth.php
- [ ] Configuración en pterodactyl.php
- [ ] Variable REGISTRATION_ENABLED en .env
- [ ] Link agregado en login.blade.php
- [ ] Permisos establecidos
- [ ] Cache limpiado
- [ ] Rutas verificadas con `route:list`
- [ ] Acceso probado en navegador

---

## 🎉 ¡Instalación Completada!

Tu sistema de registro está listo. Accede a:

**https://you-domain/auth/register**

---

**Versión:** 2.0.0  
**Compatible con:** Pterodactyl v1.12.0  
**Fecha:** Enero 2025
