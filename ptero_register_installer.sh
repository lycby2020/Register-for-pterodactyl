#!/bin/bash

###############################################################################
# PTERODACTYL v1.12.0 - REGISTRO DE USUARIOS - INSTALADOR SIMPLIFICADO
# Probado y funcionando 100%
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  PTERODACTYL v1.12 - REGISTRO USUARIOS   ║${NC}"
echo -e "${BLUE}║  Instalador Simplificado v3.0            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Root check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Ejecuta como root: sudo bash install.sh${NC}"
   exit 1
fi

# Detectar directorio
PTERO_DIR="/var/www/pterodactyl"
if [ ! -d "$PTERO_DIR" ]; then
    echo -e "${RED}❌ Pterodactyl no encontrado en $PTERO_DIR${NC}"
    exit 1
fi

cd "$PTERO_DIR"
echo -e "${GREEN}✓ Pterodactyl encontrado${NC}"

# Backup rápido
echo -e "${YELLOW}⏳ Creando backup...${NC}"
BACKUP_DIR="backups/register-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -f "routes/auth.php" ] && cp routes/auth.php "$BACKUP_DIR/"
echo -e "${GREEN}✓ Backup: $BACKUP_DIR${NC}"

# 1. CONTROLADOR
echo -e "${YELLOW}⏳ Creando controlador...${NC}"
mkdir -p app/Http/Controllers/Auth
cat > app/Http/Controllers/Auth/RegisterController.php << 'EOF'
<?php
namespace Pterodactyl\Http\Controllers\Auth;

use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Illuminate\Support\Facades\Hash;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Support\Str;

class RegisterController extends Controller
{
    public function __construct()
    {
        $this->middleware('guest');
    }

    public function showRegistrationForm()
    {
        return view('auth.register');
    }

    public function register(Request $request)
    {
        $request->validate([
            'username' => 'required|string|min:3|max:255|unique:users|regex:/^[a-zA-Z0-9_]+$/',
            'email' => 'required|email|max:255|unique:users',
            'password' => 'required|string|min:8|confirmed',
            'name_first' => 'required|string|max:255',
            'name_last' => 'required|string|max:255',
        ]);

        $user = User::forceCreate([
            'uuid' => Str::uuid()->toString(),
            'username' => $request->username,
            'email' => $request->email,
            'name_first' => $request->name_first,
            'name_last' => $request->name_last,
            'password' => Hash::make($request->password),
            'root_admin' => false,
            'language' => 'en',
        ]);

        auth()->login($user);
        
        return redirect('/')->with('success', '¡Cuenta creada exitosamente!');
    }
}
EOF
echo -e "${GREEN}✓ Controlador creado${NC}"

# 2. VISTA
echo -e "${YELLOW}⏳ Creando vista...${NC}"
cat > resources/views/auth/register.blade.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Registro - {{ config('app.name', 'Pterodactyl') }}</title>
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
    <style>
        body { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; display: flex; align-items: center; }
        .register-card { background: white; border-radius: 10px; box-shadow: 0 10px 40px rgba(0,0,0,0.2); }
        .btn-register { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border: none; }
        .btn-register:hover { opacity: 0.9; }
    </style>
</head>
<body>
    <div class="container">
        <div class="row justify-content-center">
            <div class="col-md-6">
                <div class="register-card p-4">
                    <h2 class="text-center mb-4">Crear Cuenta</h2>
                    
                    @if ($errors->any())
                        <div class="alert alert-danger">
                            <ul class="mb-0">
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
                                    <label>Nombre</label>
                                    <input type="text" name="name_first" class="form-control" value="{{ old('name_first') }}" required autofocus>
                                </div>
                            </div>
                            <div class="col-md-6">
                                <div class="form-group">
                                    <label>Apellido</label>
                                    <input type="text" name="name_last" class="form-control" value="{{ old('name_last') }}" required>
                                </div>
                            </div>
                        </div>

                        <div class="form-group">
                            <label>Usuario</label>
                            <input type="text" name="username" class="form-control" value="{{ old('username') }}" required>
                        </div>

                        <div class="form-group">
                            <label>Email</label>
                            <input type="email" name="email" class="form-control" value="{{ old('email') }}" required>
                        </div>

                        <div class="form-group">
                            <label>Contraseña</label>
                            <input type="password" name="password" class="form-control" required>
                            <small class="text-muted">Mínimo 8 caracteres</small>
                        </div>

                        <div class="form-group">
                            <label>Confirmar Contraseña</label>
                            <input type="password" name="password_confirmation" class="form-control" required>
                        </div>

                        <button type="submit" class="btn btn-register btn-block text-white">
                            Registrarse
                        </button>

                        <div class="text-center mt-3">
                            <a href="{{ route('auth.login') }}">¿Ya tienes cuenta? Inicia sesión</a>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
EOF
echo -e "${GREEN}✓ Vista creada${NC}"

# 3. RUTAS
echo -e "${YELLOW}⏳ Agregando rutas...${NC}"
if ! grep -q "RegisterController" routes/auth.php 2>/dev/null; then
    cat >> routes/auth.php << 'EOF'

// Sistema de Registro
Route::get('/register', 'Auth\RegisterController@showRegistrationForm')->name('auth.register');
Route::post('/register', 'Auth\RegisterController@register');
EOF
    echo -e "${GREEN}✓ Rutas agregadas${NC}"
else
    echo -e "${YELLOW}⚠ Rutas ya existen${NC}"
fi

# 4. PERMISOS
echo -e "${YELLOW}⏳ Configurando permisos...${NC}"
chown -R www-data:www-data "$PTERO_DIR"
chmod -R 755 storage bootstrap/cache
echo -e "${GREEN}✓ Permisos configurados${NC}"

# 5. CACHE
echo -e "${YELLOW}⏳ Limpiando cache...${NC}"
php artisan route:clear > /dev/null 2>&1
php artisan config:clear > /dev/null 2>&1
php artisan cache:clear > /dev/null 2>&1
php artisan view:clear > /dev/null 2>&1
echo -e "${GREEN}✓ Cache limpiado${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         ✓ INSTALACIÓN COMPLETA           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🔗 Accede a: ${YELLOW}https://tu-dominio.com/auth/register${NC}"
echo ""
echo -e "${YELLOW}Verificar instalación:${NC}"
echo -e "  php artisan route:list | grep register"
echo ""
