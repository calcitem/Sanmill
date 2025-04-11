// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// string_helper.dart

String removeBracketedContent(String input) {
  // Define regex patterns for each type of bracket
  final RegExp parentheses = RegExp(r'\([^()]*\)');
  final RegExp squareBrackets = RegExp(r'\[[^\[\]]*\]');
  final RegExp curlyBraces = RegExp(r'\{[^{}]*\}');

  String result = input;

  // Remove content inside parentheses
  result = result.replaceAll(parentheses, '');

  // Remove content inside square brackets
  result = result.replaceAll(squareBrackets, '');

  // Remove content inside curly braces
  result = result.replaceAll(curlyBraces, '');

  return result;
}

/// Applies the transformations you listed to the given text.
String transformOutside(String text, Map<String, String> replacements) {
  String result = text.toLowerCase();
  replacements.forEach((String pattern, String replacement) {
    result = result.replaceAll(pattern, replacement);
  });
  return result;
}

/// Returns a new string in which the parts **outside** any brackets are
/// transformed using the provided replacements. The text
/// **inside** brackets (including nested) remains unchanged.
String processOutsideBrackets(String input, Map<String, String> replacements) {
  // A stack to track opening brackets and handle nesting
  final List<String> bracketStack = <String>[];

  // Buffers to accumulate text
  final StringBuffer finalOutput = StringBuffer();
  final StringBuffer outsideBuffer = StringBuffer();
  final StringBuffer insideBuffer = StringBuffer();

  // Helper to flush the outside buffer with transformations
  void flushOutsideBuffer() {
    if (outsideBuffer.isEmpty) {
      return;
    }
    // Apply transformations
    final String transformed =
        transformOutside(outsideBuffer.toString(), replacements);
    finalOutput.write(transformed);
    outsideBuffer.clear();
  }

  // Helper to flush the inside buffer without transformations
  void flushInsideBuffer() {
    if (insideBuffer.isEmpty) {
      return;
    }
    finalOutput.write(insideBuffer.toString());
    insideBuffer.clear();
  }

  // A map for matching brackets
  final Map<String, String> matchingBrackets = <String, String>{
    ']': '[',
    '}': '{',
    ')': '(',
  };

  for (int i = 0; i < input.length; i++) {
    final String c = input[i];

    // Check if this character is an opening bracket
    if (c == '[' || c == '{' || c == '(') {
      // If we were outside, flush the outside text first
      if (bracketStack.isEmpty) {
        flushOutsideBuffer();
      }

      // Now we are switching to inside bracket
      bracketStack.add(c);
      // Write the bracket character itself to the inside buffer
      insideBuffer.write(c);
    }
    // Check if this character is a closing bracket
    else if (c == ']' || c == '}' || c == ')') {
      if (bracketStack.isNotEmpty && bracketStack.last == matchingBrackets[c]) {
        // We are inside brackets, so write to insideBuffer
        insideBuffer.write(c);
        bracketStack.removeLast();

        // If we've just closed the last bracket, we move back to "outside"
        if (bracketStack.isEmpty) {
          flushInsideBuffer();
        }
      } else {
        // If mismatched or unexpected bracket, handle as normal char (or decide on error)
        // Here we just treat it as text (outside or inside).
        if (bracketStack.isEmpty) {
          outsideBuffer.write(c);
        } else {
          insideBuffer.write(c);
        }
      }
    } else {
      // Normal character (not a bracket)
      if (bracketStack.isEmpty) {
        // We are outside any bracket
        outsideBuffer.write(c);
      } else {
        // We are inside bracket(s)
        insideBuffer.write(c);
      }
    }
  }

  // If we end and there's still stuff outside
  if (outsideBuffer.isNotEmpty) {
    flushOutsideBuffer();
  }

  // If there's any remaining inside text (unclosed bracket),
  // we’ll just flush it as-is:
  if (insideBuffer.isNotEmpty) {
    flushInsideBuffer();
  }

  return finalOutput.toString();
}
