import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

enum CutMode { round, truncate, twoDecimal }

enum EntryMode { normal, time }

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _display = '0';
  String _expression = '';
  double? _accumulator;
  String _pendingOp = '';
  double _lastOperand = 0;
  String _lastOperation = '';
  bool _justCalculated = false;
  bool _waitingForOperand = false;
  double _memory = 0.0;
  double _grandTotal = 0.0;
  EntryMode _mode = EntryMode.normal;
  CutMode _cutMode = CutMode.twoDecimal;
  bool _showingGrandTotal = false;
  bool _showingMemory = false;
  Timer? _autoOffTimer;
  bool _isScreenOff = false;
  Timer? _screenOffTimer;

  @override
  void initState() {
    super.initState();
    _resetAutoOffTimer();
  }

  @override
  void dispose() {
    _autoOffTimer?.cancel();
    _screenOffTimer?.cancel();
    super.dispose();
  }

  void _resetAutoOffTimer() {
    _autoOffTimer?.cancel();
    _autoOffTimer = Timer(const Duration(minutes: 10), () {
      _pressOff();
    });
  }

  double? _displayToDouble() {
    if (_mode == EntryMode.normal) {
      return double.tryParse(_display.replaceAll(',', ''));
    } else {
      // HMS mode: convert HH:MM:SS to seconds
      final parts = _display.split(':');
      if (parts.length == 3) {
        final h = double.tryParse(parts[0]) ?? 0;
        final m = double.tryParse(parts[1]) ?? 0;
        final s = double.tryParse(parts[2]) ?? 0;
        return h * 3600 + m * 60 + s;
      } else if (parts.length == 2) {
        final h = double.tryParse(parts[0]) ?? 0;
        final m = double.tryParse(parts[1]) ?? 0;
        return h * 3600 + m * 60;
      }
      return double.tryParse(_display);
    }
  }

  String _secondsToHMS(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return 'Error';
    final neg = seconds < 0;
    seconds = seconds.abs();
    int totalSeconds = seconds.round();
    final h = totalSeconds ~/ 3600;
    totalSeconds -= h * 3600;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds - (m * 60);
    final hh = h.toString();
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return (neg ? '-' : '') + '$hh:$mm:$ss';
  }

  String _formatNumber(double value) {
    if (value.isNaN || value.isInfinite) return 'Error';

    // Handle very large numbers with scientific notation
    if (value.abs() >= 100000000) {
      return value.toStringAsExponential(2);
    }

    String result;
    switch (_cutMode) {
      case CutMode.truncate:
        result = value.truncate().toString();
        break;
      case CutMode.round:
        result = value.round().toString();
        break;
      case CutMode.twoDecimal:
        if (value == value.roundToDouble()) {
          result = value.toStringAsFixed(0);
        } else {
          result = value.toStringAsFixed(2);
          result = result.replaceFirst(RegExp(r'\.?0+$'), '');
        }
        break;
    }

    if (result == '-0') result = '0';

    // Add thousands separators for large numbers
    if (value.abs() >= 1000 && !result.contains('e')) {
      final parts = result.split('.');
      parts[0] = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      result = parts.join('.');
    }

    return result;
  }

  void _enterDigit(String digit) {
    _resetAutoOffTimer();
    setState(() {
      if (_justCalculated || _showingGrandTotal || _showingMemory) {
        _display = digit == '.' ? '0.' : digit;
        _expression = '';
        _justCalculated = false;
        _showingGrandTotal = false;
        _showingMemory = false;
        _waitingForOperand = false;
        return;
      }

      if (_waitingForOperand) {
        _display = digit == '.' ? '0.' : digit;
        _waitingForOperand = false;
        return;
      }

      if (_mode == EntryMode.normal) {
        if (_display == '0' && digit != '.') {
          _display = digit;
        } else {
          if (digit == '.' && _display.contains('.')) return;
          if (_display.length >= 12) return; // Limit display length
          _display += digit;
        }
      } else {
        // HMS mode digit entry
        String compact = _display.replaceAll(':', '');
        if (compact == '0') compact = '';
        compact += digit;
        if (compact.length > 6) compact = compact.substring(compact.length - 6);
        compact = compact.padLeft(6, '0');
        final hh = compact.substring(0, compact.length - 4);
        final mm = compact.substring(compact.length - 4, compact.length - 2);
        final ss = compact.substring(compact.length - 2);
        _display = '${int.parse(hh)}:$mm:$ss';
      }
    });
  }

  void _pressClear() {
    _resetAutoOffTimer();
    setState(() {
      _display = '0';
      _justCalculated = false;
      _showingGrandTotal = false;
      _showingMemory = false;
    });
  }

  void _pressAllClear() {
    _resetAutoOffTimer();
    setState(() {
      _display = '0';
      _expression = '';
      _accumulator = null;
      _pendingOp = '';
      _lastOperand = 0;
      _lastOperation = '';
      _justCalculated = false;
      _waitingForOperand = false;
      _showingGrandTotal = false;
      _showingMemory = false;
    });
  }

  void _applyUnary(String op) {
    _resetAutoOffTimer();
    setState(() {
      final value = _displayToDouble();
      if (value == null) return;

      double result;
      switch (op) {
        case '+/-':
          if (_display.startsWith('-')) {
            _display = _display.substring(1);
          } else if (_display != '0') {
            _display = '-$_display';
          }
          return;
        case '√':
          if (value < 0) {
            _display = 'Error';
            return;
          }
          result = sqrt(value);
          break;
        case '%':
          result = value / 100;
          break;
        default:
          return;
      }

      if (_mode == EntryMode.normal) {
        _display = _formatNumber(result);
      } else {
        _display = _secondsToHMS(result);
      }
      _justCalculated = true;
    });
  }

  void _pressOperator(String op) {
    _resetAutoOffTimer();
    setState(() {
      final currentValue = _displayToDouble() ?? 0;

      if (_accumulator != null &&
          _pendingOp.isNotEmpty &&
          !_waitingForOperand) {
        _computePending();
      }

      _accumulator = _displayToDouble() ?? 0;
      _pendingOp = op;
      _waitingForOperand = true;
      _justCalculated = false;
      _showingGrandTotal = false;
      _showingMemory = false;

      // Update expression display
      String displayValue = _mode == EntryMode.normal
          ? _formatNumber(_accumulator!)
          : _secondsToHMS(_accumulator!);
      _expression = '$displayValue $op';
    });
  }

  void _computePending() {
    if (_pendingOp.isEmpty || _accumulator == null) return;

    final right = _displayToDouble() ?? 0;
    double result;

    switch (_pendingOp) {
      case '+':
        result = _accumulator! + right;
        break;
      case '-':
        result = _accumulator! - right;
        break;
      case '×':
        result = _accumulator! * right;
        break;
      case '÷':
        if (right == 0) {
          _display = 'Error';
          _expression = '';
          _accumulator = null;
          _pendingOp = '';
          return;
        }
        result = _accumulator! / right;
        break;
      default:
        result = right;
    }

    _lastOperand = right;
    _lastOperation = _pendingOp;

    if (_mode == EntryMode.normal) {
      _display = _formatNumber(result);
    } else {
      _display = _secondsToHMS(result);
    }

    _accumulator = result;
    _pendingOp = '';
    _expression = '';
    _justCalculated = true;

    // Add to Grand Total (only for completed calculations)
    _grandTotal += _mode == EntryMode.normal ? result : result;
  }

  void _pressEquals() {
    _resetAutoOffTimer();
    setState(() {
      if (_pendingOp.isNotEmpty && _accumulator != null) {
        _computePending();
      } else if (_justCalculated && _lastOperation.isNotEmpty) {
        // Repeat last operation (Casio behavior)
        final currentValue = _displayToDouble() ?? 0;
        double result;

        switch (_lastOperation) {
          case '+':
            result = currentValue + _lastOperand;
            break;
          case '-':
            result = currentValue - _lastOperand;
            break;
          case '×':
            result = currentValue * _lastOperand;
            break;
          case '÷':
            if (_lastOperand == 0) {
              _display = 'Error';
              return;
            }
            result = currentValue / _lastOperand;
            break;
          default:
            return;
        }

        if (_mode == EntryMode.normal) {
          _display = _formatNumber(result);
        } else {
          _display = _secondsToHMS(result);
        }

        _grandTotal += _mode == EntryMode.normal ? result : result;
      }

      _waitingForOperand = false;
      _showingGrandTotal = false;
      _showingMemory = false;
    });
  }

  void _memoryPlus() {
    _resetAutoOffTimer();
    setState(() {
      final value = _mode == EntryMode.normal
          ? (_displayToDouble() ?? 0)
          : (_displayToDouble() ?? 0);
      _memory += value;
    });
  }

  void _memoryMinus() {
    _resetAutoOffTimer();
    setState(() {
      final value = _mode == EntryMode.normal
          ? (_displayToDouble() ?? 0)
          : (_displayToDouble() ?? 0);
      _memory -= value;
    });
  }

  void _memoryRecall() {
    _resetAutoOffTimer();
    setState(() {
      _showingMemory = true;
      if (_mode == EntryMode.normal) {
        _display = _formatNumber(_memory);
      } else {
        _display = _secondsToHMS(_memory);
      }
      _justCalculated = true;
      _expression = '';
    });
  }

  void _memoryClear() {
    _resetAutoOffTimer();
    setState(() {
      _memory = 0.0;
    });
  }

  void _pressGT() {
    _resetAutoOffTimer();
    setState(() {
      _showingGrandTotal = true;
      if (_mode == EntryMode.normal) {
        _display = _formatNumber(_grandTotal);
      } else {
        _display = _secondsToHMS(_grandTotal);
      }
      _expression = '';
    });
  }

  void _clearGrandTotal() {
    _resetAutoOffTimer();
    setState(() {
      _grandTotal = 0.0;
      if (_showingGrandTotal) {
        _display = _mode == EntryMode.normal ? '0' : _secondsToHMS(0.0);
        _showingGrandTotal = false;
      }
    });
  }

  void _toggleHMS() {
    _resetAutoOffTimer();
    setState(() {
      if (_mode == EntryMode.normal) {
        // Convert decimal hours to HMS
        final hours = _displayToDouble() ?? 0;
        final seconds = hours * 3600;
        _display = _secondsToHMS(seconds);
        _mode = EntryMode.time;
      } else {
        // Convert HMS to decimal hours
        final seconds = _displayToDouble() ?? 0;
        final hours = seconds / 3600;
        _display = _formatNumber(hours);
        _mode = EntryMode.normal;
      }
      _justCalculated = true;
      _expression = '';
    });
  }

  void _pressEnter() {
    _resetAutoOffTimer();
    setState(() {
      _accumulator = _displayToDouble() ?? 0;
      _pendingOp = '';
      _justCalculated = true;
      _expression = '';
    });
  }

  void _simulateScreenOff() {
    setState(() {
      _isScreenOff = true;
    });

    // Cancel any existing screen off timer
    _screenOffTimer?.cancel();

    // // Set a timer to automatically turn the screen back on after 5 seconds
    // _screenOffTimer = Timer(const Duration(seconds: 5), () {
    //   _turnScreenOn();
    // });
  }

  void _turnScreenOn() {
    setState(() {
      _isScreenOff = false;
    });
    _resetAutoOffTimer(); // Reset the auto-off timer when screen is turned on
  }

  void _pressOff() {
    if (_isScreenOff) {
      _turnScreenOn();
    } else {
      _simulateScreenOff();
    }
  }

  String _getStatusIndicators() {
    String indicators = '';
    if (_mode == EntryMode.time) indicators += 'HMS ';
    if (_memory != 0.0) indicators += 'M ';
    if (_grandTotal != 0.0) indicators += 'GT';
    return indicators.trim();
  }

  Widget _buildButton({
    required String label,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
    Color? backgroundColor,
    Color? textColor,
    bool isWide = false,
    required double buttonHeight,
  }) {
    return Expanded(
      flex: isWide ? 2 : 1,
      child: Container(
        margin: const EdgeInsets.all(1.5),
        height: buttonHeight,
        child: NeumorphicButton(
          onPressed: onPressed,
          // onLongPress: onLongPress,
          style: NeumorphicStyle(
            boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(6)),
            depth: 2,
            intensity: 0.7,
            surfaceIntensity: 0.1,
            color: backgroundColor ?? const Color(0xFFE8E8E0),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor ?? Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onButton(String label) {
    if (RegExp(r'^[0-9]$').hasMatch(label) || label == '.') {
      _enterDigit(label);
    } else {
      switch (label) {
        case 'C':
          _pressClear();
          break;
        case 'AC':
          _pressAllClear();
          break;
        case '+/-':
        case '%':
        case '√':
          _applyUnary(label);
          break;
        case '+':
        case '-':
        case '×':
        case '÷':
          _pressOperator(label);
          break;
        case '=':
          _pressEquals();
          break;
        case 'M+':
          _memoryPlus();
          break;
        case 'M-':
          _memoryMinus();
          break;
        case 'MR':
          _memoryRecall();
          break;
        case 'MC':
          _memoryClear();
          break;
        case 'GT':
          _pressGT();
          break;
        case 'HMS':
          _toggleHMS();
          break;
        case '▶':
          _pressEnter();
          break;
        case 'OFF':
          // _pressAllClear();
          _pressOff();
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isScreenOff ? Colors.black : const Color(0xFFE8E8E0),
      body: SafeArea(
        minimum: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_isScreenOff) {
              // Show black screen with a small indicator that calculator is off
              return GestureDetector(
                onTap: _turnScreenOn,
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.power_settings_new,
                          color: Colors.grey[700],
                          size: 40,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Press any button to turn on',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final screenHeight = constraints.maxHeight;
            final screenWidth = constraints.maxWidth;
            final isSmallScreen = screenHeight < 600 || screenWidth < 360;
            final isLargeScreen = screenHeight > 800;

            // Calculate dynamic button height based on available space
            final availableHeight =
                screenHeight - 120; // Subtract header and display height
            final buttonHeight = (availableHeight / 6).clamp(
              40.0,
              70.0,
            ); // Min 40, Max 70

            // Adjust display height based on screen size
            final displayHeight = isLargeScreen
                ? 80
                : (isSmallScreen ? 60 : 70);

            return Column(
              children: [
                SizedBox(height: isSmallScreen ? 4 : 8),
                // CASIO Header - made more compact
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'CASIO',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 20 : 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'HL-122TV',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 10 : 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'TIME CALCULATIONS',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 8 : 10,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: isSmallScreen ? 12 : 16),

                // Display - dynamic height
                Neumorphic(
                  style: NeumorphicStyle(
                    depth: -4,
                    boxShape: NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(12),
                    ),
                    color: const Color(0xFFB5C0A0),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    height: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Status indicators
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _getStatusIndicators(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Expression (smaller text)
                        if (_expression.isNotEmpty)
                          Container(
                            width: double.infinity,
                            child: Text(
                              _expression,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        const Spacer(),
                        // Main display
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Text(
                            _display,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: isSmallScreen ? 12 : 18),
                Text(
                  "HMS Calculator",
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 12 : 18),

                // Button Grid - auto-adjusted height
                Expanded(
                  child: Column(
                    spacing: 4,
                    children: [
                      // Row 1: HMS | +/- | ▶ | GT | OFF
                      SizedBox(
                        height: buttonHeight,
                        child: Row(
                          children: [
                            _buildButton(
                              label: 'HMS',
                              onPressed: () => _onButton('HMS'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '+/-',
                              onPressed: () => _onButton('+/-'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '▶',
                              onPressed: () => _onButton('▶'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: 'GT',
                              onPressed: () => _onButton('GT'),
                              onLongPress: _clearGrandTotal,
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: 'OFF',
                              onPressed: () => _onButton('OFF'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                          ],
                        ),
                      ),

                      // Row 2: MC | MR | M- | M+ | ÷
                      SizedBox(
                        height: buttonHeight,
                        child: Row(
                          children: [
                            _buildButton(
                              label: 'MC',
                              onPressed: () => _onButton('MC'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: 'MR',
                              onPressed: () => _onButton('MR'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: 'M-',
                              onPressed: () => _onButton('M-'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: 'M+',
                              onPressed: () => _onButton('M+'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '÷',
                              onPressed: () => _onButton('÷'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                          ],
                        ),
                      ),

                      // Row 3: % | 7 | 8 | 9 | ×
                      SizedBox(
                        height: buttonHeight,
                        child: Row(
                          children: [
                            _buildButton(
                              label: '%',
                              onPressed: () => _onButton('%'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '7',
                              onPressed: () => _onButton('7'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '8',
                              onPressed: () => _onButton('8'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '9',
                              onPressed: () => _onButton('9'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '×',
                              onPressed: () => _onButton('×'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                          ],
                        ),
                      ),

                      // Row 4: √ | 4 | 5 | 6 | -
                      SizedBox(
                        height: buttonHeight,
                        child: Row(
                          children: [
                            _buildButton(
                              label: '√',
                              onPressed: () => _onButton('√'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '4',
                              onPressed: () => _onButton('4'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '5',
                              onPressed: () => _onButton('5'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '6',
                              onPressed: () => _onButton('6'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '-',
                              onPressed: () => _onButton('-'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                          ],
                        ),
                      ),

                      // Row 5: C | 1 | 2 | 3 | +
                      SizedBox(
                        height: buttonHeight,
                        child: Row(
                          children: [
                            _buildButton(
                              label: 'C',
                              onPressed: () => _onButton('C'),
                              backgroundColor: Colors.red[600],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '1',
                              onPressed: () => _onButton('1'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '2',
                              onPressed: () => _onButton('2'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '3',
                              onPressed: () => _onButton('3'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '+',
                              onPressed: () => _onButton('+'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                          ],
                        ),
                      ),

                      // Row 6: AC | 0 | . | =
                      SizedBox(
                        height: buttonHeight,
                        child: Row(
                          children: [
                            _buildButton(
                              label: 'AC',
                              onPressed: () => _onButton('AC'),
                              backgroundColor: Colors.red[700],
                              textColor: Colors.white,
                              isWide: true,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '0',
                              onPressed: () => _onButton('0'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '.',
                              onPressed: () => _onButton('.'),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                            _buildButton(
                              label: '=',
                              onPressed: () => _onButton('='),
                              backgroundColor: Colors.grey[800],
                              textColor: Colors.white,
                              buttonHeight: buttonHeight,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 4 : 8),
                      Text(
                        "© Developed by Prasis",
                        style: TextStyle(
                          fontSize: isSmallScreen ? 8 : 10,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
