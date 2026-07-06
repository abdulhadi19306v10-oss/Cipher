import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _register() async {
    setState(() => _isLoading = true);
    final result = await ApiService.register(
      _usernameController.text,
      _emailController.text,
      _passwordController.text,
    );
    setState(() => _isLoading = false);

    if (result['success']) {
      Navigator.pushReplacementNamed(context, '/home');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration Successful! QR Code generated.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Error registering')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Deep space gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                begin: Alignment.bottomRight,
                end: Alignment.topLeft,
              ),
            ),
          ),
          // Subtle glowing orbs
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00A884).withOpacity(0.2),
                boxShadow: const [BoxShadow(color: Color(0xFF00A884), blurRadius: 100, spreadRadius: 50)],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF5865F2).withOpacity(0.3),
                boxShadow: const [BoxShadow(color: Color(0xFF5865F2), blurRadius: 100, spreadRadius: 50)],
              ),
            ),
          ),
          // Glassmorphic Card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(32.0),
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Create an account',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text('Join the most secure network.', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                        const SizedBox(height: 40),
                        _buildGlassTextField(
                          controller: _usernameController,
                          label: 'USERNAME',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 20),
                        _buildGlassTextField(
                          controller: _emailController,
                          label: 'EMAIL',
                          icon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 20),
                        _buildGlassTextField(
                          controller: _passwordController,
                          label: 'PASSWORD',
                          icon: Icons.lock_outline,
                          obscure: true,
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5865F2),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 10,
                              shadowColor: const Color(0xFF5865F2).withOpacity(0.5),
                            ),
                            onPressed: _isLoading ? null : _register,
                            child: _isLoading 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                              : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                          child: const Text('Already have an account?', style: TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassTextField({required TextEditingController controller, required String label, required IconData icon, bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.5)),
        filled: true,
        fillColor: Colors.black.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF5865F2), width: 1.5),
        ),
      ),
    );
  }
}
