// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
  String get moveList => ' 1.    g1    b4\n'
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
      '[ (3,4), (2,7), (2,4), (2,3), (3,5), (2,1), (3,6), -(2,3), (2,3), (3,3), (2,5), (3,2), -(2,3), (2,3), (1,6), (1,8), (2,8), (3,8), (1,5), (1,4), (1,6)->(1,7), (2,5)->(2,6), (3,5)->(2,5), (1,4)->(1,3), (2,5)->(3,5), -(2,6), (1,8)->(1,1), (2,4)->(2,5), -(2,1), (2,7)->(3,7), (1,7)->(2,7), (2,3)->(2,4), (3,2)->(3,1), (1,3)->(2,3), (1,5)->(1,4), (1,1)->(2,1), (1,4)->(1,3), (2,1)->(2,2), -(2,7), (2,5)->(2,6), (2,4)->(2,5), (3,1)->(3,2), -(2,3), (3,8)->(3,1), (3,3)->(2,3), (3,7)->(2,7), (2,3)->(3,3), -(2,2), (2,5)->(1,1), (3,5)->(2,5), (2,7)->(2,1), -(2,5), (3,3)->(2,3), (1,1)->(3,3), (2,6)->(2,5), (3,3)->(1,1), -(2,5), (3,4)->(3,3), -(2,1), ]';

  @override
  String get nonstandardMoveList => ' 1. (3,4)  2. (2,7)\n'
      ' 3. (2,4)  4. (2,3)\n'
      ' 5. (3,5)  6. (2,1)\n'
      ' 7. (3,6)  8. -(2,3)\n'
      ' 9. (2,3) 10. (3,3)\n'
      '11. (2,5) 12. (3,2)\n'
      '13. -(2,3) 14. (2,3)\n'
      '15. (1,6) 16. (1,8)\n'
      '17. (2,8) 18. (3,8)\n'
      '19. (1,5) 20. (1,4)\n'
      '21. (1,6)->(1,7) 22. (2,5)->(2,6)\n'
      '23. (3,5)->(2,5) 24. (1,4)->(1,3)\n'
      '25. (2,5)->(3,5) 26. -(2,6)\n'
      '27. (1,8)->(1,1) 28. (2,4)->(2,5)\n'
      '29. -(2,1) 30. (2,7)->(3,7)\n'
      '31. (1,7)->(2,7) 32. (2,3)->(2,4)\n'
      '33. (3,2)->(3,1) 34. (1,3)->(2,3)\n'
      '35. (1,5)->(1,4) 36. (1,1)->(2,1)\n'
      '37. (1,4)->(1,3) 38. (2,1)->(2,2)\n'
      '39. -(2,7) 40. (2,5)->(2,6)\n'
      '41. (2,4)->(2,5) 42. (3,1)->(3,2)\n'
      '43. -(2,3) 44. (3,8)->(3,1)\n'
      '45. (3,3)->(2,3) 46. (3,7)->(2,7)\n'
      '47. (2,3)->(3,3) 48. -(2,2)\n'
      '49. (2,5)->(1,1) 50. (3,5)->(2,5)\n'
      '51. (2,7)->(2,1) 52. -(2,5)\n'
      '53. (3,3)->(2,3) 54. (1,1)->(3,3)\n'
      '55. (2,6)->(2,5) 56. (3,3)->(1,1)\n'
      '57. -(2,5) 58. (3,4)->(3,3)59. -(2,1)';
}
