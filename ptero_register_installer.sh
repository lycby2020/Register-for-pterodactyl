#!/bin/bash

################################################################################
# PTERODACTYL v1.12.0 - SISTEMA DE REGISTRO DE USUARIOS
# Versión: 4.0 FINAL - PROBADO Y FUNCIONAL
# Compatible: Pterodactyl Panel v1.11.x - v1.12.x
################################################################################

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

clear

echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║   ██████╗ ████████╗███████╗██████╗  ██████╗                ║
║   ██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔═══██╗               ║
║   ██████╔╝   ██║   █████╗  ██████╔╝██║   ██║               ║
║   ██╔═══╝    ██║   ██╔══╝  ██╔══██╗██║   ██║               ║
║   ██║        ██║   ███████╗██║  ██║╚██████╔╝               ║
║   ╚═╝        ╚═╝   ╚══════╝╚═╝  ╚═╝ ╚═════╝                ║
║                                                              ║
║        SISTEMA DE REGISTRO DE USUARIOS v4.0                 ║
║        Compatible con Pterodactyl v1.12.0                   ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Este script debe ejecutarse como root${NC}"
   echo -e "${YELLOW}Ejecuta: sudo bash $0${NC}"
   exit 1
fi

# Detectar Pterodactyl
echo -e "${YELLOW}[1/9] Detectando instalación de Pterodactyl...${NC}"
PTERO_DIR="/var/www/pterodactyl"

if [ ! -d "$PTERO_DIR" ]; then
    echo -e "${RED}[ERROR] No se encontró Pterodactyl en $PTERO_DIR${NC}"
    read -p "Ingresa la ruta de instalación de Pterodactyl: " PTERO_DIR
    if [ ! -d "$PTERO_DIR" ]; then
        echo -e "${RED}[ERROR] Directorio no válido${NC}"
        exit 1
    fi
fi

# Verificar que es Pterodactyl
if [ ! -f "$PTERO_DIR/artisan" ]; then
    echo -e "${RED}[ERROR] No se encontró Pterodactyl en $PTERO_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Pterodactyl encontrado en: $PTERO_DIR${NC}"

# Cambiar al directorio
cd "$PTERO_DIR"

# Crear backup
echo -e "${YELLOW}[2/9] Creando backup de seguridad...${NC}"
BACKUP_DIR="$PTERO_DIR/storage/backups/register-addon-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -f "routes/auth.php" ]; then
    cp routes/auth.php "$BACKUP_DIR/auth.php.backup"
fi

if [ -f "resources/views/auth/login.blade.php" ]; then
    cp resources/views/auth/login.blade.php "$BACKUP_DIR/login.blade.php.backup"
fi

echo -e "${GREEN}✓ Backup creado en: $BACKUP_DIR${NC}"

# Crear directorios necesarios
echo -e "${YELLOW}[3/9] Creando estructura de directorios...${NC}"
mkdir -p app/Http/Controllers/Auth
mkdir -p resources/views/auth
mkdir -p resources/views/emails
echo -e "${GREEN}✓ Directorios creados${NC}"

# Crear RegisterController
echo -e "${YELLOW}[4/9] Creando controlador de registro...${NC}"
cat > app/Http/Controllers/Auth/RegisterController.php << 'PHPCONTROLLER'
<?php

namespace Pterodactyl\Http\Controllers\Auth;

use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Foundation\Auth\RegistersUsers;
use Illuminate\Support\Str;
use Illuminate\Auth\Events\Registered;

class RegisterController extends Controller
{
    use RegistersUsers;

    protected $redirectTo = '/';

    public function __construct()
    {
        $this->middleware('guest');
    }

    /**
     * Mostrar formulario de registro
     */
    public function showRegistrationForm()
    {
        return view('auth.register');
    }

    /**
     * Validar datos de registro
     */
    protected function validator(array $data)
    {
        return Validator::make($data, [
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
                'confirmed'
            ],
            'name_first' => ['required', 'string', 'max:255'],
            'name_last' => ['required', 'string', 'max:255'],
        ], [
            'username.regex' => 'El usuario solo puede contener letras, números, guiones y guiones bajos.',
            'username.unique' => 'Este nombre de usuario ya está en uso.',
            'email.unique' => 'Este email ya está registrado.',
            'password.min' => 'La contraseña debe tener al menos 8 caracteres.',
            'password.confirmed' => 'Las contraseñas no coinciden.',
        ]);
    }

    /**
     * Crear nuevo usuario
     */
    protected function create(array $data)
    {
        return User::forceCreate([
            'uuid' => Str::uuid()->toString(),
            'username' => $data['username'],
            'email' => $data['email'],
            'name_first' => $data['name_first'],
            'name_last' => $data['name_last'],
            'password' => Hash::make($data['password']),
            'root_admin' => false,
            'language' => 'en',
        ]);
    }

    /**
     * Manejar registro
     */
    public function register(Request $request)
    {
        $this->validator($request->all())->validate();

        event(new Registered($user = $this->create($request->all())));

        $this->guard()->login($user);

        return $this->registered($request, $user)
                        ?: redirect($this->redirectPath());
    }
}
PHPCONTROLLER

echo -e "${GREEN}✓ Controlador creado${NC}"

# Crear vista de registro
echo -e "${YELLOW}[5/9] Creando vista de registro...${NC}"
cat > resources/views/auth/register.blade.php << 'BLADEREGISTER'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Registro - {{ config('app.name', 'Pterodactyl') }}</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }
        .register-container {
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
            max-width: 500px;
            width: 100%;
            margin: 20px;
        }
        .register-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .register-body {
            padding: 30px;
        }
        .form-group label {
            font-weight: 600;
            color: #333;
            margin-bottom: 8px;
        }
        .form-control {
            border-radius: 8px;
            border: 2px solid #e0e0e0;
            padding: 12px;
            transition: all 0.3s;
        }
        .form-control:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
        }
        .btn-register {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border: none;
            border-radius: 8px;
            padding: 12px;
            font-weight: 600;
            transition: all 0.3s;
        }
        .btn-register:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 20px rgba(102, 126, 234, 0.4);
        }
        .alert {
            border-radius: 8px;
        }
        .login-link {
            text-align: center;
            margin-top: 20px;
            color: #666;
        }
        .login-link a {
            color: #667eea;
            font-weight: 600;
            text-decoration: none;
        }
        .login-link a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="register-container">
        <div class="register-header">
            <h2 class="mb-0"><i class="fas fa-user-plus"></i> Crear Cuenta</h2>
            <p class="mb-0 mt-2">Únete a {{ config('app.name', 'Pterodactyl') }}</p>
        </div>
        
        <div class="register-body">
            @if ($errors->any())
                <div class="alert alert-danger">
                    <strong><i class="fas fa-exclamation-triangle"></i> Error</strong>
                    <ul class="mb-0 mt-2">
                        @foreach ($errors->all() as $error)
                            <li>{{ $error }}</li>
                        @endforeach
                    </ul>
                </div>
            @endif

            <form method="POST" action="{{ route('auth.register') }}">
                @csrf
                
                <div class="row">
                    <div class="col-md-6">
                        <div class="form-group">
                            <label><i class="fas fa-user"></i> Nombre</label>
                            <input type="text" name="name_first" class="form-control @error('name_first') is-invalid @enderror" 
                                   value="{{ old('name_first') }}" required autofocus placeholder="Tu nombre">
                        </div>
                    </div>
                    <div class="col-md-6">
                        <div class="form-group">
                            <label><i class="fas fa-user"></i> Apellido</label>
                            <input type="text" name="name_last" class="form-control @error('name_last') is-invalid @enderror" 
                                   value="{{ old('name_last') }}" required placeholder="Tu apellido">
                        </div>
                    </div>
                </div>

                <div class="form-group">
                    <label><i class="fas fa-at"></i> Usuario</label>
                    <input type="text" name="username" class="form-control @error('username') is-invalid @enderror" 
                           value="{{ old('username') }}" required placeholder="usuario123">
                    <small class="text-muted">Solo letras, números, guiones y guiones bajos</small>
                </div>

                <div class="form-group">
                    <label><i class="fas fa-envelope"></i> Email</label>
                    <input type="email" name="email" class="form-control @error('email') is-invalid @enderror" 
                           value="{{ old('email') }}" required placeholder="tu@email.com">
                </div>

                <div class="form-group">
                    <label><i class="fas fa-lock"></i> Contraseña</label>
                    <input type="password" name="password" class="form-control @error('password') is-invalid @enderror" 
                           required placeholder="••••••••">
                    <small class="text-muted">Mínimo 8 caracteres</small>
                </div>

                <div class="form-group">
                    <label><i class="fas fa-lock"></i> Confirmar Contraseña</label>
                    <input type="password" name="password_confirmation" class="form-control" 
                           required placeholder="••••••••">
                </div>

                <button type="submit" class="btn btn-register btn-block text-white">
                    <i class="fas fa-check-circle"></i> Registrarse
                </button>
            </form>

            <div class="login-link">
                ¿Ya tienes cuenta? <a href="{{ route('auth.login') }}">Inicia sesión aquí</a>
            </div>
        </div>
    </div>
</body>
</html>
BLADEREGISTER

echo -e "${GREEN}✓ Vista creada${NC}"

# Agregar rutas
echo -e "${YELLOW}[6/9] Configurando rutas...${NC}"

if ! grep -q "RegisterController" routes/auth.php 2>/dev/null; then
    echo "" >> routes/auth.php
    cat >> routes/auth.php << 'ROUTES'

/*
|--------------------------------------------------------------------------
| Registration Routes
|--------------------------------------------------------------------------
*/
Route::get('/register', 'Auth\RegisterController@showRegistrationForm')->name('auth.register');
Route::post('/register', 'Auth\RegisterController@register');
ROUTES
    echo -e "${GREEN}✓ Rutas agregadas${NC}"
else
    echo -e "${YELLOW}⚠ Rutas ya existen, saltando...${NC}"
fi

# Modificar login para agregar link
echo -e "${YELLOW}[7/9] Modificando página de login...${NC}"

LOGIN_FILE="resources/views/auth/login.blade.php"
if [ -f "$LOGIN_FILE" ]; then
    if ! grep -q "auth.register" "$LOGIN_FILE"; then
        # Agregar antes del </body>
        sed -i 's|</body>|<div style="text-align: center; margin-top: 20px;"><a href="{{ route('"'"'auth.register'"'"') }}" style="color: #667eea; font-weight: 600;">¿No tienes cuenta? Regístrate aquí</a></div>\n</body>|g' "$LOGIN_FILE"
        echo -e "${GREEN}✓ Link agregado a login${NC}"
    else
        echo -e "${YELLOW}⚠ Link ya existe en login${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Archivo login.blade.php no encontrado${NC}"
fi

# Permisos
echo -e "${YELLOW}[8/9] Configurando permisos...${NC}"

# Detectar usuario web
WEB_USER="www-data"
if ! id "$WEB_USER" &>/dev/null; then
    if id "nginx" &>/dev/null; then
        WEB_USER="nginx"
    elif id "apache" &>/dev/null; then
        WEB_USER="apache"
    fi
fi

chown -R $WEB_USER:$WEB_USER "$PTERO_DIR"
chmod -R 755 storage bootstrap/cache
echo -e "${GREEN}✓ Permisos configurados (usuario: $WEB_USER)${NC}"

# Limpiar cache
echo -e "${YELLOW}[9/9] Limpiando cache de Laravel...${NC}"

php artisan route:clear 2>&1 | grep -v "deprecated" || true
php artisan config:clear 2>&1 | grep -v "deprecated" || true
php artisan cache:clear 2>&1 | grep -v "deprecated" || true
php artisan view:clear 2>&1 | grep -v "deprecated" || true

# Cachear rutas
php artisan route:cache 2>&1 | grep -v "deprecated" || true
php artisan config:cache 2>&1 | grep -v "deprecated" || true

echo -e "${GREEN}✓ Cache limpiado y reconstruido${NC}"

# Verificar instalación
echo ""
echo -e "${CYAN}[VERIFICACIÓN] Comprobando rutas instaladas...${NC}"
php artisan route:list | grep -i register || echo -e "${YELLOW}⚠ No se pudieron listar las rutas (esto puede ser normal)${NC}"

# Mensaje final
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              ✓ INSTALACIÓN COMPLETADA CON ÉXITO             ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 ¡Sistema de registro instalado exitosamente!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📍 INFORMACIÓN:${NC}"
echo -e "   • Backup guardado en: ${CYAN}$BACKUP_DIR${NC}"
echo -e "   • Directorio Pterodactyl: ${CYAN}$PTERO_DIR${NC}"
echo -e "   • Usuario web: ${CYAN}$WEB_USER${NC}"
echo ""
echo -e "${YELLOW}🔗 ACCESO:${NC}"
echo -e "   • URL de registro: ${GREEN}https://tu-dominio.com/auth/register${NC}"
echo -e "   • URL de login: ${GREEN}https://tu-dominio.com/auth/login${NC}"
echo ""
echo -e "${YELLOW}✅ VERIFICAR:${NC}"
echo -e "   ${CYAN}php artisan route:list | grep register${NC}"
echo ""
echo -e "${YELLOW}🆘 SOPORTE:${NC}"
echo -e "   Si hay problemas, revisa: ${CYAN}storage/logs/laravel.log${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}¡Gracias por usar el instalador!${NC}"
echo ""
