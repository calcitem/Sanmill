import 'package:flutter/material.dart';

class BlurHolder extends StatelessWidget {
  const BlurHolder({
    super.key,
    required this.diameter,
    required this.squareSide,
  });

  final double diameter, squareSide;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all((squareSide - diameter) / 2),
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(diameter / 2),
        color: Colors.transparent, // TODO: Change to Blur color
      ),
    );
  }
}
