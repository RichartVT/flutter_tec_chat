import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _smsCodeCtrl = TextEditingController();

  final _formPhoneKey = GlobalKey<FormState>();
  final _formCodeKey = GlobalKey<FormState>();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // Android / iOS
  String? _verificationId;

  // Web
  ConfirmationResult? _webConfirmationResult;

  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _codeSent = false;
  String? _errorMessage;

  Timer? _resendTimer;
  int _secondsToResend = 0;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _smsCodeCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _secondsToResend = 60;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsToResend <= 1) {
        timer.cancel();
        setState(() {
          _secondsToResend = 0;
        });
      } else {
        setState(() {
          _secondsToResend--;
        });
      }
    });
  }

  Future<void> _sendCode() async {
    if (!_formPhoneKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSendingCode = true;
      _errorMessage = null;
    });

    final rawPhone = _phoneCtrl.text.trim();
    String phoneNumber = rawPhone;

    // Normaliza: si son 10 dígitos sin prefijo, asumimos +52 México
    if (!rawPhone.startsWith('+')) {
      if (rawPhone.length == 10) {
        phoneNumber = '+52$rawPhone';
      } else {
        phoneNumber = '+$rawPhone';
      }
    }

    try {
      // 🌐 WEB
      if (kIsWeb) {
        final result = await _auth.signInWithPhoneNumber(phoneNumber);
        if (!mounted) return;

        setState(() {
          _webConfirmationResult = result;
          _codeSent = true;
        });
        _startResendTimer();
        return;
      }

      // 🍎 iOS simulador: de momento solo mensaje (para evitar crashes)
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        setState(() {
          _errorMessage =
              'La verificación por SMS en iOS simulador requiere configuración '
              'extra (APNs y dispositivo real).\n\n'
              'Para esta tarea prueba en Web (Chrome) o en un dispositivo Android.\n\n'
              'Cuando tengas un iPhone real, aquí activamos verifyPhoneNumber().';
        });
        return;
      }

      // 🤖 Android (y otros)
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCredential = await _auth.signInWithCredential(credential);
            debugPrint(
              'Usuario autenticado automáticamente: '
              '${userCredential.user?.uid}',
            );

            if (!kIsWeb) {
              await _ensureUserDocument(userCredential.user);
            }

            _goToNextScreen();
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _errorMessage =
                  'Error al completar la verificación automática. Intenta manualmente.';
            });
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() {
            _errorMessage = _firebaseErrorMessage(e);
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
          });
          _startResendTimer();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          _verificationId = verificationId;
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _firebaseErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Ocurrió un error inesperado. Intenta nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSendingCode = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    if (!_formCodeKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isVerifyingCode = true;
      _errorMessage = null;
    });

    try {
      UserCredential userCredential;

      if (kIsWeb) {
        if (_webConfirmationResult == null) {
          setState(() {
            _errorMessage = 'No se ha enviado ningún código todavía.';
          });
          return;
        }

        userCredential = await _webConfirmationResult!.confirm(
          _smsCodeCtrl.text.trim(),
        );
      } else {
        if (_verificationId == null) {
          setState(() {
            _errorMessage = 'No se ha enviado ningún código todavía.';
          });
          return;
        }

        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: _smsCodeCtrl.text.trim(),
        );

        userCredential = await _auth.signInWithCredential(credential);
      }

      await _ensureUserDocument(userCredential.user);
      if (mounted) _goToNextScreen();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _firebaseErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error genérico en _verifyCode: $e');
      setState(() {
        _errorMessage = 'Ocurrió un error al verificar el código.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingCode = false;
        });
      }
    }
  }

  Future<void> _ensureUserDocument(User? user) async {
    if (user == null) return;

    // // 👇 IMPORTANTE: para evitar el error "client is offline" en Web
    // if (kIsWeb) {
    //   debugPrint(
    //     'Saltando Firestore en Web (modo demo). '
    //     'El usuario se autenticó pero no se guarda en collection users.',
    //   );
    //   return;
    // }

    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        await docRef.set({
          'uid': user.uid,
          'phoneNumber': user.phoneNumber,
          'emailTec': null,
          'displayName': null,
          'avatarUrl': null,
          'about': 'Disponible',
          'role': 'alumno',
          'createdAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.update({'lastSeen': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      // En producción podrías reportar el error, aquí solo lo logeamos.
      debugPrint('Error en _ensureUserDocument (no bloquea login): $e');
    }
  }

  void _goToNextScreen() {
    Navigator.of(context).pushReplacementNamed('/home');
  }

  String _firebaseErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'El número de teléfono no es válido.';
      case 'too-many-requests':
        return 'Demasiados intentos. Inténtalo de nuevo más tarde.';
      case 'session-expired':
        return 'La sesión ha expirado. Solicita un nuevo código.';
      case 'invalid-verification-code':
        return 'El código ingresado no es correcto.';
      case 'network-request-failed':
        return 'Parece que no hay conexión a Internet.';
      default:
        return 'Error de autenticación: ${e.code}';
    }
  }

  void _resetFlow() {
    setState(() {
      _codeSent = false;
      _verificationId = null;
      _webConfirmationResult = null;
      _smsCodeCtrl.clear();
      _errorMessage = null;
    });
    _resendTimer?.cancel();
    _secondsToResend = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio con número de teléfono'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _codeSent ? _buildCodeView() : _buildPhoneView(),
        ),
      ),
    );
  }

  Widget _buildPhoneView() {
    return Padding(
      key: const ValueKey('phone-view'),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'TecChat Celaya',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ingresa tu número de teléfono para enviar un código de verificación vía SMS.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Form(
            key: _formPhoneKey,
            child: TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Número de teléfono',
                hintText: '+52 1 555 555 5555 ó 10 dígitos',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Ingresa tu número de teléfono.';
                if (!v.startsWith('+') && v.length != 10) {
                  return 'Ingresa 10 dígitos o un número con código de país (+).';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSendingCode ? null : _sendCode,
              child: _isSendingCode
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enviar código'),
            ),
          ),
          const SizedBox(height: 12),
          if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildCodeView() {
    return Padding(
      key: const ValueKey('code-view'),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'Verificación de código',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Hemos enviado un código SMS al número:\n${_phoneCtrl.text.trim()}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Form(
            key: _formCodeKey,
            child: TextFormField(
              controller: _smsCodeCtrl,
              decoration: const InputDecoration(
                labelText: 'Código SMS',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Ingresa el código que recibiste.';
                if (v.length < 6) return 'El código debe tener 6 dígitos.';
                return null;
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isVerifyingCode ? null : _verifyCode,
              child: _isVerifyingCode
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirmar código'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_secondsToResend > 0)
                Text(
                  'Puedes reenviar en $_secondsToResend s',
                  style: const TextStyle(color: Colors.grey),
                )
              else
                TextButton(
                  onPressed: _isSendingCode ? null : _sendCode,
                  child: const Text('Reenviar código'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _isVerifyingCode ? null : _resetFlow,
            child: const Text('Cambiar número'),
          ),
        ],
      ),
    );
  }
}
