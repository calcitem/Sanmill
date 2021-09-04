#!/bin/bash

sed -i "2s/\"de-ch\"/\"de_CH\"/" intl_de_ch.arb
sed -i "2s/\"no\"/\"nn\"/" intl_nn.arb
sed -i "2s/\"pt-br\"/\"pt\"/" intl_pt.arb
sed -i "2s/\"zh-CN\"/\"zh\"/" intl_zh.arb
sed -i "2s/\"zh-Hant\"/\"zh_Hant\"/" intl_zh_Hant.arb
