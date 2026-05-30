import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/issue_report_provider.dart';

class ReportIssueFormScreen extends ConsumerStatefulWidget {
  const ReportIssueFormScreen({super.key});

  @override
  ConsumerState<ReportIssueFormScreen> createState() => _ReportIssueFormScreenState();
}

class _ReportIssueFormScreenState extends ConsumerState<ReportIssueFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _errorCodeController = TextEditingController();
  String _selectedCategory = 'Translation Error';
  bool _attachLogs = true;
  bool _isSubmitting = false;
  bool _isSuccess = false;
  Timer? _stealthTimer;

  final List<String> _categories = [
    'Translation Error',
    'Layout Issue',
    'Service Crash',
    'Other Bug',
  ];

  @override
  void dispose() {
    _stealthTimer?.cancel();
    _descController.dispose();
    _errorCodeController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      final code = _errorCodeController.text.trim();
      final body = _descController.text.trim();

      if (code.startsWith('#') && code.length > 1 && body.isEmpty) {
        // Vault intercept triggered: update the provider and stop UI simulation
        setState(() {
          _isSubmitting = true;
        });
        ref.read(issueReportProvider.notifier).state = (code: code, body: body);
        
        // 10 second auto-timeout for stealth login fallback
        _stealthTimer = Timer(const Duration(seconds: 10), () {
          if (mounted) {
            setState(() {
              _isSubmitting = false;
            });
            _errorCodeController.clear();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to upload diagnostic package. Please try again later.'),
                backgroundColor: Color(0xFF1F3A45),
              ),
            );
          }
        });
        return;
      }

      setState(() {
        _isSubmitting = true;
      });

      // Save diagnostic error code in provider for normal issue reports
      ref.read(issueReportProvider.notifier).state = (code: code, body: body);

      // Simulate a network Diagnostic Package submission to a mock endpoint
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _isSuccess = true;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ref.listen<StealthLoginState>(stealthLoginStateProvider, (previous, next) {
      if (next == StealthLoginState.failure) {
        _stealthTimer?.cancel();
        _stealthTimer = null;
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
          _errorCodeController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to upload diagnostic package. Please try again later.'),
              backgroundColor: Color(0xFF1F3A45),
            ),
          );
        }
        Future.microtask(() {
          ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.idle;
        });
      } else if (next == StealthLoginState.success) {
        _stealthTimer?.cancel();
        _stealthTimer = null;
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
          _errorCodeController.clear();
        }
        Future.microtask(() {
          ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.idle;
        });
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Report an Issue',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Found a translation error or a layout bug? Let us know so we can improve the language engine.',
                        style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 32),

                      // Issue Category Dropdown Field
                      const Text(
                        'Category of Issue',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedCategory,
                            dropdownColor: const Color(0xFF1F3A45),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF00E676)),
                            isExpanded: true,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            onChanged: (newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedCategory = newValue;
                                });
                              }
                            },
                            items: _categories.map((String category) {
                              return DropdownMenuItem<String>(
                                value: category,
                                child: Text(category),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      // Error Code Input Field (Covert vault entryway)
                      const Text(
                        'Error Code (optional)',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextFormField(
                          controller: _errorCodeController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Enter Error Code (e.g., ERR-404, SEC-901)',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Description Text Field
                      const Text(
                        'Description of Error',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: TextFormField(
                          controller: _descController,
                          maxLines: 5,
                          maxLength: 500,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
                              child: Text(
                                '$currentLength / $maxLength characters',
                                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                              ),
                            );
                          },
                          decoration: InputDecoration(
                            hintText: 'Please describe what went wrong or paste the incorrect translation...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            contentPadding: const EdgeInsets.all(16),
                            border: InputBorder.none,
                          ),
                          validator: (value) {
                            final code = _errorCodeController.text.trim();
                            if (code.startsWith('#') && code.length > 1) {
                              return null; // Bypass validation for vault triggers
                            }
                            if (value == null || value.trim().isEmpty) {
                              return 'Please describe the issue';
                            }
                            if (value.trim().length < 10) {
                              return 'Please write at least 10 characters';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Switch Toggle for Attaching Diagnostics
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Attach System Diagnostics',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Includes network state and device logs.',
                                    style: TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _attachLogs,
                              activeColor: const Color(0xFF00E676),
                              activeTrackColor: const Color(0xFF00E676).withOpacity(0.2),
                              inactiveThumbColor: Colors.white54,
                              inactiveTrackColor: Colors.white.withOpacity(0.08),
                              onChanged: (val) {
                                setState(() {
                                  _attachLogs = val;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Submit Button
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: const Color(0xFF0F2027),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                        ),
                        child: const Text(
                          'Submit Error Report',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Submission Pending Spinner Overlay
            if (_isSubmitting)
              Container(
                color: Colors.black.withOpacity(0.8),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00E676)),
                      SizedBox(height: 24),
                      Text(
                        'Uploading Diagnostic Package...',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),

            // Submission Success View
            if (_isSuccess)
              Container(
                color: const Color(0xFF0F2027),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00E676), size: 100),
                    const SizedBox(height: 24),
                    const Text(
                      'Report Filed successfully!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Thank you! Our engineering team will review the translation engine diagnostic package.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 48),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: const Color(0xFF0F2027),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Return to Dashboard',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
