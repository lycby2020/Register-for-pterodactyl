#!/bin/bash

# Pterodactyl User Registration Addon - Auto Installer
# Compatible con Pterodactyl v1.12.0
# Este script instala automáticamente el sistema de registro de usuarios

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   PTERODACTYL v1.12.0 USER REGISTRATION ADDON           ║
║   Versión 2.0.0 - Optimizado para 1.12.0                ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar permisos de root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root${NC}" 
   exit 1
fi

# Detectar directorio de Pterodactyl
echo -e "${YELLOW}Detectando instalación de Pterodactyl...${NC}"
PTERO_DIR="/var/www/pterodactyl"

if [ ! -d "$PTERO_DIR" ]; then
    read -p "No se encontró Pterodactyl en /var/www/pterodactyl. Ingresa la ruta: " PTERO_DIR
    if [ ! -d "$PTERO_DIR" ]; then
        echo -e "${RED}Directorio no válido. Saliendo.${NC}"
        exit 1
    fi
fi

# Verificar versión de Pterodactyl
if [ -f "$PTERO_DIR/config/app.php" ]; then
    echo -e "${GREEN}✓ Pterodactyl encontrado en: $PTERO_DIR${NC}"
else
    echo -e "${RED}No se puede verificar la instalación de Pterodactyl${NC}"
    exit 1
fi

# Backup
echo -e "${YELLOW}Creando backup de seguridad...${NC}"
BACKUP_DIR="$PTERO_DIR/backups/registration-addon-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -f "$PTERO_DIR/routes/auth.php" ] && cp "$PTERO_DIR/routes/auth.php" "$BACKUP_DIR/"
echo -e "${GREEN}✓ Backup creado en: $BACKUP_DIR${NC}"

# Crear directorios necesarios
mkdir -p "$PTERO_DIR/app/Http/Controllers/Auth"
mkdir -p "$PTERO_DIR/resources/scripts/components/auth/RegisterContainer"
mkdir -p "$PTERO_DIR/resources/views/emails"

# 1. Crear controlador de registro (actualizado para v1.12.0)
echo -e "${YELLOW}Creando controlador de registro...${NC}"
cat > "$PTERO_DIR/app/Http/Controllers/Auth/RegisterController.php" << 'PHPEOF'
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
PHPEOF

echo -e "${GREEN}✓ Controlador creado${NC}"

# 2. Crear vista de registro moderna (compatible con v1.12.0)
echo -e "${YELLOW}Creando vista de registro...${NC}"
cat > "$PTERO_DIR/resources/views/auth/register.blade.php" << 'BLADEEOF'
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
BLADEEOF

echo -e "${GREEN}✓ Vista creada${NC}"

# 3. Crear email de bienvenida
echo -e "${YELLOW}Creando template de email...${NC}"
cat > "$PTERO_DIR/resources/views/emails/welcome.blade.php" << 'EMAILEOF'
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
EMAILEOF

echo -e "${GREEN}✓ Template de email creado${NC}"

# 4. Agregar configuración al config
echo -e "${YELLOW}Configurando opciones...${NC}"
CONFIG_FILE="$PTERO_DIR/config/pterodactyl.php"

if [ -f "$CONFIG_FILE" ]; then
    if ! grep -q "registration_enabled" "$CONFIG_FILE"; then
        sed -i "/^return \[/a\\    // Configuración del sistema de registro\\n    'auth' => [\\n        'registration_enabled' => env('REGISTRATION_ENABLED', true),\\n    ]," "$CONFIG_FILE"
        echo -e "${GREEN}✓ Configuración agregada${NC}"
    fi
fi

# 5. Agregar variable al .env
ENV_FILE="$PTERO_DIR/.env"
if [ -f "$ENV_FILE" ] && ! grep -q "REGISTRATION_ENABLED" "$ENV_FILE"; then
    echo "" >> "$ENV_FILE"
    echo "# Sistema de Registro" >> "$ENV_FILE"
    echo "REGISTRATION_ENABLED=true" >> "$ENV_FILE"
    echo -e "${GREEN}✓ Variable de entorno agregada${NC}"
fi

# 6. Configurar rutas
echo -e "${YELLOW}Configurando rutas...${NC}"
ROUTES_FILE="$PTERO_DIR/routes/auth.php"

if [ -f "$ROUTES_FILE" ]; then
    if ! grep -q "RegisterController" "$ROUTES_FILE"; then
        cat >> "$ROUTES_FILE" << 'ROUTESEOF'

/*
|--------------------------------------------------------------------------
| Custom Registration Routes
|--------------------------------------------------------------------------
*/
Route::middleware('guest')->group(function () {
    Route::get('/register', 'Auth\RegisterController@showRegistrationForm')->name('auth.register');
    Route::post('/register', 'Auth\RegisterController@register');
});
ROUTESEOF
        echo -e "${GREEN}✓ Rutas agregadas${NC}"
    else
        echo -e "${YELLOW}⚠ Las rutas ya existen${NC}"
    fi
else
    echo -e "${RED}✗ No se encontró routes/auth.php${NC}"
    echo -e "${YELLOW}Creando archivo de rutas...${NC}"
    cat > "$ROUTES_FILE" << 'ROUTESEOF'
<?php

use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Custom Registration Routes
|--------------------------------------------------------------------------
*/
Route::middleware('guest')->group(function () {
    Route::get('/register', 'Auth\RegisterController@showRegistrationForm')->name('auth.register');
    Route::post('/register', 'Auth\RegisterController@register');
});
ROUTESEOF
    echo -e "${GREEN}✓ Archivo de rutas creado${NC}"
fi

# 7. Modificar vista de login
echo -e "${YELLOW}Modificando página de login...${NC}"
LOGIN_VIEW="$PTERO_DIR/resources/views/auth/login.blade.php"

if [ -f "$LOGIN_VIEW" ]; then
    if ! grep -q "auth.register" "$LOGIN_VIEW"; then
        # Buscar el botón de login y agregar el link después
        sed -i '/<button.*type="submit"/,/<\/button>/a\
            <div class="mt-6 text-center">\
                <a href="{{ route('"'"'auth.register'"'"') }}" class="text-sm text-blue-500 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300">\
                    ¿No tienes cuenta? <strong>Regístrate aquí</strong>\
                </a>\
            </div>' "$LOGIN_VIEW"
        echo -e "${GREEN}✓ Link de registro agregado al login${NC}"
    else
        echo -e "${YELLOW}⚠ El link ya existe en login${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No se encontró la vista de login${NC}"
fi

# 8. Establecer permisos correctos
echo -e "${YELLOW}Configurando permisos...${NC}"
cd "$PTERO_DIR"

# Detectar usuario web
if id "www-data" &>/dev/null; then
    WEB_USER="www-data"
elif id "nginx" &>/dev/null; then
    WEB_USER="nginx"
elif id "apache" &>/dev/null; then
    WEB_USER="apache"
else
    WEB_USER="www-data"
fi

chown -R $WEB_USER:$WEB_USER "$PTERO_DIR"
find "$PTERO_DIR" -type f -exec chmod 644 {} \;
find "$PTERO_DIR" -type d -exec chmod 755 {} \;
chmod -R 755 "$PTERO_DIR/storage" "$PTERO_DIR/bootstrap/cache"

echo -e "${GREEN}✓ Permisos configurados para usuario: $WEB_USER${NC}"

# 9. Limpiar cache de Laravel
echo -e "${YELLOW}Limpiando cache de Laravel...${NC}"
cd "$PTERO_DIR"

php artisan config:clear 2>/dev/null || echo "Config cache limpiado"
php artisan cache:clear 2>/dev/null || echo "Cache limpiado"
php artisan view:clear 2>/dev/null || echo "View cache limpiado"
php artisan route:clear 2>/dev/null || echo "Route cache limpiado"

# Optimizar (opcional pero recomendado)
php artisan config:cache 2>/dev/null || echo "Config cacheado"
php artisan route:cache 2>/dev/null || echo "Routes cacheadas"

echo -e "${GREEN}✓ Cache limpiado y optimizado${NC}"

# 10. Crear archivo de documentación
echo -e "${YELLOW}Creando documentación...${NC}"
cat > "$PTERO_DIR/REGISTER_ADDON_README.md" << 'READMEEOF'
# Pterodactyl User Registration Addon

## 📋 Información

Este addon agrega un sistema completo de registro de usuarios para Pterodactyl v1.12.0

## ✨ Características

- ✅ Formulario de registro moderno y responsive
- ✅ Validación completa de datos
- ✅ Emails de bienvenida automáticos
- ✅ Integración perfecta con Pterodactyl
- ✅ Sistema de activación/desactivación
- ✅ Compatible con dark mode

## 🎛️ Configuración

### Habilitar/Deshabilitar Registro

Edita tu archivo `.env`:
```env
REGISTRATION_ENABLED=true  # o false para deshabilitar
```

### Configurar Emails

Agrega en tu `.env`:
```env
MAIL_DRIVER=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=tu@email.com
MAIL_PASSWORD=tu_contraseña
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@tudominio.com
MAIL_FROM_NAME="Tu Panel"
```

## 🔗 Rutas

- Registro: `https://tu-panel.com/auth/register`
- Login: `https://tu-panel.com/auth/login`

## 🎨 Personalización

### Modificar la vista
Edita: `resources/views/auth/register.blade.php`

### Modificar el email
Edita: `resources/views/emails/welcome.blade.php`

### Modificar validaciones
Edita: `app/Http/Controllers/Auth/RegisterController.php`

## 🛠️ Comandos útiles

```bash
# Limpiar cache
php artisan config:clear
php artisan cache:clear
php artisan view:clear

# Ver rutas
php artisan route:list | grep register

# Probar envío de emails
php artisan tinker
>>> Mail::raw('Test', function($msg) { $msg->to('tu@email.com')->subject('Test'); });
```

## 🐛 Solución de problemas

### Error 404 en /register
```bash
php artisan route:clear
php artisan route:cache
```

### Permisos incorrectos
```bash
sudo chown -R www-data:www-data /var/www/pterodactyl
sudo chmod -R 755 /var/www/pterodactyl/storage
```

### No se envían emails
- Verifica configuración SMTP en `.env`
- Revisa logs: `storage/logs/laravel.log`
- Prueba con Mailtrap.io para testing

## 📦 Desinstalación

```bash
# Eliminar archivos
rm /var/www/pterodactyl/app/Http/Controllers/Auth/RegisterController.php
rm /var/www/pterodactyl/resources/views/auth/register.blade.php

# Restaurar rutas
# Edita manualmente: routes/auth.php y elimina las rutas de registro

# Limpiar cache
php artisan config:clear
php artisan route:clear
```

## 📞 Soporte

- Backup guardado en: `backups/registration-addon-[fecha]/`
- Logs en: `storage/logs/laravel.log`

## 🔒 Seguridad

Los usuarios registrados:
- NO son administradores por defecto
- Deben verificar su email (si está configurado)
- Tienen contraseñas hasheadas con bcrypt

---
Instalado: $(date)
Versión: 2.0.0
Compatible: Pterodactyl v1.12.0
READMEEOF

echo -e "${GREEN}✓ Documentación creada${NC}"

# Resumen final
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║            ✓ INSTALACIÓN COMPLETADA CON ÉXITO           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${GREEN}🎉 ¡Sistema de registro instalado correctamente!${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📋 INFORMACIÓN IMPORTANTE:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  🔗 URL de registro: ${GREEN}https://tu-dominio.com/auth/register${NC}"
echo -e "  📁 Backup guardado en: ${YELLOW}$BACKUP_DIR${NC}"
echo -e "  📖 Documentación: ${YELLOW}$PTERO_DIR/REGISTER_ADDON_README.md${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━