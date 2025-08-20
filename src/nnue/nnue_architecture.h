/*
  Stockfish, a UCI chess playing engine derived from Glaurung 2.1
  Copyright (C) 2004-2022 The Stockfish developers (see AUTHORS file)

  Stockfish is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Stockfish is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// Input features and network structure used in NNUE evaluation function

#ifndef NNUE_ARCHITECTURE_H_INCLUDED
#define NNUE_ARCHITECTURE_H_INCLUDED

#include "nnue_common.h"

#include "features/nine_mill.h"

#include "layers/input_slice.h"
#include "layers/affine_transform.h"
#include "layers/clipped_relu.h"

namespace Stockfish::Eval::NNUE {

  // Input features used in evaluation function (Nine Men's Morris)
  using FeatureSet = Features::NineMill;

  // Number of input feature dimensions after conversion
  // Transformed feature width per perspective. Must match PyTorch L1.
  // Nine Men's Morris trainer uses L1 = 1536 (per perspective), so total input
  // to the first FC is 2 * 1536.
  constexpr IndexType TransformedFeatureDimensions = 1536;
  constexpr IndexType PSQTBuckets = 8;
  constexpr IndexType LayerStacks = 8;

  namespace Layers {

    // Define network structure
    using InputLayer = InputSlice<TransformedFeatureDimensions * 2>;
    // Hidden sizes matched to smaller Nine Men's Morris model
    using HiddenLayer1 = ClippedReLU<AffineTransform<InputLayer, 16>>;
    using HiddenLayer2 = ClippedReLU<AffineTransform<HiddenLayer1, 32>>;
    using OutputLayer = AffineTransform<HiddenLayer2, 1>;

  }  // namespace Layers

  using Network = Layers::OutputLayer;

  static_assert(TransformedFeatureDimensions % MaxSimdWidth == 0, "");
  static_assert(Network::OutputDimensions == 1, "");
  static_assert(std::is_same<Network::OutputType, std::int32_t>::value, "");

}  // namespace Stockfish::Eval::NNUE

#endif // #ifndef NNUE_ARCHITECTURE_H_INCLUDED
