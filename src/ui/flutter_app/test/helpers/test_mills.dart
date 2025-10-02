// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_mills.dart

abstract class TestGame {
  const TestGame();

  String get moveList;

  String? get movesSinceRemove;

  String get recorderToString;

  String get nonstandardMoveList;
}

class WinLessThanThreeGame extends TestGame {
  const WinLessThanThreeGame();

  @override
  String get moveList =>
      ' 1.    g1    b4\n'
      ' 2.    f2    f4\n'
      ' 3.    d1    d6\n'
      ' 4.    a1xf4    f4\n'
      ' 5.    g4    d2\n'
      ' 6.    g7xf4    f4\n'
      ' 7.    c3    c5\n'
      ' 8.    b6    a7\n'
      ' 9.    d3    e3\n'
      '10.    c3-c4    d2-b2\n'
      '11.    d1-d2    e3-e4\n'
      '12.    d2-d1xb2    c5-d5\n'
      '13.    f2-d2xd6    b4-a4\n'
      '14.    c4-b4    f4-f2\n'
      '15.    g7-d7    e4-f4\n'
      '16.    d3-e3    d5-d6\n'
      '17.    e3-e4    d6-f6xb4\n'
      '18.    d2-b2    f2-d2\n'
      '19.    d7-g7xf4    a7-d7\n'
      '20.    g4-f4    a4-b4\n'
      '21.    f4-g4xf6    d2-d5\n'
      '22.    d1-d2    b4-d6xd2\n'
      '23.    g4-f4    d5-g4\n'
      '24.    b2-d2    g4-d5xd2\n'
      '25.    g1-g4xd6';

  @override
  String? get movesSinceRemove => null;

  @override
  String get recorderToString =>
      '[ g4, g7, f4, d3, c4, b2, a4, xd3, d3, c3, b4, d7, xd3, d3, a7, a1, d1, a4, a5, a4, a7-g7, b4-b6, c4-b4, a4-a3, b4-c4, xb6, a1-a1, f4-b4, xb2, g7-c7, g7-g7, d3-f4, d7-d1, a3-d3, a5-a4, a1-b2, a4-a3, b2-b2, xg7, b4-b6, f4-b4, d1-d7, xd3, a4-d1, c3-d3, c7-g7, d3-c3, xb2, b4-a1, c4-b4, g7-b2, xb4, c3-d3, a1-c3, b6-b4, c3-a1, xb4, g4-c3, xb2, ]';

  @override
  String get nonstandardMoveList =>
      ' 1. g4  2. g7\n'
      ' 3. f4  4. d3\n'
      ' 5. c4  6. b2\n'
      ' 7. a4  8. xd3\n'
      ' 9. d3 10. c3\n'
      '11. b4 12. d7\n'
      '13. xd3 14. d3\n'
      '15. a7 16. a1\n'
      '17. d1 18. a4\n'
      '19. a5 20. a4\n'
      '21. a7-g7 22. b4-b6\n'
      '23. c4-b4 24. a4-a3\n'
      '25. b4-c4 26. xb6\n'
      '27. a1-a1 28. f4-b4\n'
      '29. xb2 30. g7-c7\n'
      '31. g7-g7 32. d3-f4\n'
      '33. d7-d1 34. a3-d3\n'
      '35. a5-a4 36. a1-b2\n'
      '37. a4-a3 38. b2-b2\n'
      '39. xg7 40. b4-b6\n'
      '41. f4-b4 42. d1-d7\n'
      '43. xd3 44. a4-d1\n'
      '45. c3-d3 46. c7-g7\n'
      '47. d3-c3 48. xb2\n'
      '49. b4-a1 50. c4-b4\n'
      '51. g7-b2 52. xb4\n'
      '53. c3-d3 54. a1-c3\n'
      '55. b6-b4 56. c3-a1\n'
      '57. xb4 58. g4-c359. xb2';
}
