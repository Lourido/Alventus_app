import 'package:flutter/material.dart';

import '../services/odoo_service.dart';
import '../services/storage_service.dart';
import '../config/odoo_config.dart';
import 'home_screen.dart';
import 'package:alventus_app/widgets/speech/mic_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final OdooService _odooService = OdooService();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    print('🔍 _login: Intentando autenticar...');

    final result = await _odooService.authenticate(
      login: _loginController.text.trim(),
      password: _passwordController.text,
    );

    print('🔍 _login: Resultado de authenticate = $result');

    if (!mounted) return;

    if (result['success'] == true) {
      print('🔍 _login: Login exitoso, guardando credenciales...');

      final storageService = StorageService();

      try {
        await storageService.saveCredentials(
          uid: result['uid'] as int,
          db: OdooConfig.database,
          login: _loginController.text.trim(),
          password: _passwordController.text,
        );

        print('✅ Credenciales guardadas para modo offline');

        // Obtener el nombre real del usuario desde Odoo
        final realName = await _odooService.fetchUserName(result['uid'] as int);
        if (realName != null && realName.isNotEmpty) {
          await storageService.saveUserName(realName);
          print('✅ Nombre de usuario guardado: $realName');
        } else {
          await storageService.saveUserName(_loginController.text.trim());
        }
      } catch (e) {
        print('❌ _login: Error al guardar credenciales: $e');
      }

      if (!mounted) return;

      // Obtener el nombre guardado para pasarlo al HomeScreen
      final savedUserName = await storageService.getUserName();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            uid: result['uid'],
            userName: savedUserName ?? _loginController.text.trim(),
          ),
        ),
      );
    } else {
      print('❌ _login: Login fallido: ${result['error']}');
      setState(() {
        _errorMessage = result['error'] ?? 'Error de autenticación';
        _isLoading = false;
      });
    }
  }

  // Entrar en modo offline con credenciales guardadas
  Future<void> _tryOfflineMode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final storageService = StorageService();
    final savedUid = await storageService.getUid();
    final savedUserName = await storageService.getUserName();

    if (!mounted) return;

    if (savedUid != null) {
      // Hay credenciales guardadas: entrar en modo offline
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              HomeScreen(uid: savedUid, userName: savedUserName ?? 'Usuario'),
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No hay credenciales guardadas. Inicia sesión con conexión primero.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo real de Alventus
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/logo_alventus.png',
                        width: 150,
                        height: 150,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          print('❌ Error al cargar el logo: $error');
                          return Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.business,
                              size: 80,
                              color: Colors.blue,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Nombre de la empresa
                  const Text(
                    'Alventus y Años Luz',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A3A5C),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtítulo
                  const Text(
                    'Viajes',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Mensaje de error
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Campo de usuario
                  MicTextField(
                    controller: _loginController,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Introduce tu usuario';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Campo de contraseña
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Introduce tu contraseña';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Botón de login
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A3A5C),
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Iniciar sesión',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botón de modo offline
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _tryOfflineMode,
                      icon: const Icon(Icons.wifi_off),
                      label: const Text('Entrar sin conexión'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
