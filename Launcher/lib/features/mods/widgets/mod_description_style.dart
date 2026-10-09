import 'package:flutter/painting.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

// Keep the existing font sizes, weights and spacing supplied by MarkdownBody.
// Code and quotes need a dark fill so light text stays readable inside them.
MarkdownStyleSheet modDescriptionStyle({
  required Color textColor,
  required Color linkColor,
  required Color blockBackgroundColor,
}) {
  final text = TextStyle(color: textColor);
  final blockDecoration = BoxDecoration(
    color: blockBackgroundColor,
    borderRadius: BorderRadius.circular(2),
  );
  return MarkdownStyleSheet(
    a: TextStyle(color: linkColor, decoration: TextDecoration.underline),
    p: text,
    code: text.copyWith(backgroundColor: blockBackgroundColor),
    h1: text,
    h2: text,
    h3: text,
    h4: text,
    h5: text,
    h6: text,
    blockquote: text,
    img: text,
    listBullet: text,
    tableHead: text,
    tableBody: text,
    blockquoteDecoration: blockDecoration,
    codeblockDecoration: blockDecoration,
  );
}
