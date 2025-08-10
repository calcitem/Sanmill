#!/usr/bin/env python3
"""
训练日志记录器 - 记录每轮迭代的效果到表格文件
"""

import os
import csv
import json
import time
from datetime import datetime
from typing import Dict, List, Optional, Any


class TrainingLogger:
    """记录训练过程中每轮迭代的效果数据"""
    
    def __init__(self, log_dir: str = './temp/stats', session_name: str = None):
        """
        初始化训练日志器
        
        Args:
            log_dir: 日志保存目录
            session_name: 训练会话名称，如果为None则自动生成
        """
        self.log_dir = log_dir
        if not os.path.exists(log_dir):
            os.makedirs(log_dir)
        
        # 生成会话名称和文件名
        if session_name is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            session_name = f"training_{timestamp}"
        
        self.session_name = session_name
        self.csv_file = os.path.join(log_dir, f"{session_name}_log.csv")
        self.json_file = os.path.join(log_dir, f"{session_name}_log.json")
        
        # CSV 表头
        self.csv_headers = [
            'iteration',           # 迭代轮次
            'timestamp',           # 时间戳
            'self_play_games',     # 自对弈局数
            'teacher_examples',    # 教师样本数
            'training_examples',   # 总训练样本数
            'training_epochs',     # 训练轮数
            'training_loss',       # 训练损失
            'prev_wins',           # 旧模型胜局
            'new_wins',            # 新模型胜局
            'draws',               # 和局数
            'win_rate',            # 新模型胜率
            'model_accepted',      # 是否接受新模型
            'perfect_wins',        # 对完美库胜局
            'perfect_losses',      # 对完美库败局
            'perfect_draws',       # 对完美库和局
            'perfect_draw_rate',   # 对完美库和棋率
            'iteration_time',      # 本轮耗时（秒）
            'total_time',          # 累计耗时（秒）
            'notes'                # 备注
        ]
        
        # 初始化文件
        self._init_files()
        
        # 记录开始时间
        self.start_time = time.time()
        self.last_time = self.start_time
        
        # 数据缓存
        self.data_cache: List[Dict] = []
    
    def _init_files(self):
        """初始化日志文件"""
        # 创建 CSV 文件和表头
        if not os.path.exists(self.csv_file):
            with open(self.csv_file, 'w', newline='', encoding='utf-8') as f:
                writer = csv.DictWriter(f, fieldnames=self.csv_headers)
                writer.writeheader()
        
        # 创建 JSON 文件
        if not os.path.exists(self.json_file):
            with open(self.json_file, 'w', encoding='utf-8') as f:
                json.dump({"session_name": self.session_name, 
                          "start_time": datetime.now().isoformat(),
                          "iterations": []}, f, indent=2, ensure_ascii=False)
    
    def log_iteration(self, 
                     iteration: int,
                     self_play_games: int = 0,
                     teacher_examples: int = 0,
                     training_examples: int = 0,
                     training_epochs: int = 0,
                     training_loss: Optional[float] = None,
                     prev_wins: int = 0,
                     new_wins: int = 0,
                     draws: int = 0,
                     model_accepted: bool = False,
                     perfect_wins: int = 0,
                     perfect_losses: int = 0,
                     perfect_draws: int = 0,
                     notes: str = ""):
        """
        记录一轮迭代的结果
        
        Args:
            iteration: 迭代轮次
            self_play_games: 自对弈局数
            teacher_examples: 教师样本数
            training_examples: 总训练样本数
            training_epochs: 训练轮数
            training_loss: 训练损失
            prev_wins: 旧模型胜局
            new_wins: 新模型胜局
            draws: 和局数
            model_accepted: 是否接受新模型
            perfect_wins: 对完美库胜局
            perfect_losses: 对完美库败局
            perfect_draws: 对完美库和局
            notes: 备注信息
        """
        current_time = time.time()
        iteration_time = current_time - self.last_time
        total_time = current_time - self.start_time
        
        # 计算胜率和和棋率
        total_games = prev_wins + new_wins + draws
        win_rate = new_wins / total_games if total_games > 0 else 0.0
        
        perfect_total = perfect_wins + perfect_losses + perfect_draws
        perfect_draw_rate = perfect_draws / perfect_total if perfect_total > 0 else 0.0
        
        # 创建记录
        record = {
            'iteration': iteration,
            'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            'self_play_games': self_play_games,
            'teacher_examples': teacher_examples,
            'training_examples': training_examples,
            'training_epochs': training_epochs,
            'training_loss': f"{training_loss:.6f}" if training_loss is not None else "",
            'prev_wins': prev_wins,
            'new_wins': new_wins,
            'draws': draws,
            'win_rate': f"{win_rate:.3f}",
            'model_accepted': "是" if model_accepted else "否",
            'perfect_wins': perfect_wins,
            'perfect_losses': perfect_losses,
            'perfect_draws': perfect_draws,
            'perfect_draw_rate': f"{perfect_draw_rate:.3f}" if perfect_total > 0 else "",
            'iteration_time': f"{iteration_time:.1f}",
            'total_time': f"{total_time:.1f}",
            'notes': notes
        }
        
        # 写入 CSV
        with open(self.csv_file, 'a', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=self.csv_headers)
            writer.writerow(record)
        
        # 更新 JSON 文件
        self._update_json(record)
        
        # 更新时间
        self.last_time = current_time
        
        # 控制台输出
        print(f"\n📊 第 {iteration} 轮训练结果已记录:")
        print(f"   胜率: {win_rate:.3f} ({new_wins}/{total_games})")
        if perfect_total > 0:
            print(f"   对完美库和棋率: {perfect_draw_rate:.3f} ({perfect_draws}/{perfect_total})")
        print(f"   模型: {'✅ 接受' if model_accepted else '❌ 拒绝'}")
        print(f"   耗时: {iteration_time:.1f}s")
        print(f"   日志: {self.csv_file}")

        # 绘制曲线图
        try:
            self.plot_metrics()
        except Exception as e:
            # 按用户偏好，让错误直接暴露
            assert False, f"Plot metrics failed: {e}"

    def plot_metrics(self) -> None:
        """每轮更新一次图像，保存至 log_dir 下，展示 loss / win_rate / perfect_draw_rate / acceptance."""
        try:
            import matplotlib
            matplotlib.use('Agg')  # 后端无界面
            import matplotlib.pyplot as plt
        except Exception as e:
            raise AssertionError("matplotlib is required to plot metrics. Install via: pip install matplotlib") from e

        # 读取 JSON 数据
        with open(self.json_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        iters = data.get('iterations', [])
        if not iters:
            return

        def _to_float(v, default=None):
            try:
                if v == '' or v is None:
                    return default
                return float(v)
            except Exception:
                return default

        xs = [int(r.get('iteration', idx + 1)) for idx, r in enumerate(iters)]
        losses = [_to_float(r.get('training_loss'), None) for r in iters]
        win_rates = [_to_float(r.get('win_rate'), 0.0) for r in iters]
        perfect_draw_rates = [_to_float(r.get('perfect_draw_rate'), None) for r in iters]
        accepted = [1.0 if str(r.get('model_accepted')) in ("是", "True", "true", "1") else 0.0 for r in iters]

        # 构建子图
        fig, axes = plt.subplots(2, 2, figsize=(10, 6))
        ax1, ax2 = axes[0]
        ax3, ax4 = axes[1]

        # Loss
        if any(v is not None for v in losses):
            xs_loss = [x for x, v in zip(xs, losses) if v is not None]
            ys_loss = [v for v in losses if v is not None]
            ax1.plot(xs_loss, ys_loss, marker='o', label='val_loss')
        ax1.set_title('Validation Loss')
        ax1.set_xlabel('Iteration')
        ax1.set_ylabel('Loss')
        ax1.grid(True, alpha=0.3)

        # Win rate
        ax2.plot(xs, win_rates, marker='o', color='tab:green', label='win_rate')
        ax2.set_title('Win Rate (new vs prev)')
        ax2.set_xlabel('Iteration')
        ax2.set_ylabel('Rate')
        ax2.set_ylim(0.0, 1.0)
        ax2.grid(True, alpha=0.3)

        # Perfect draw rate
        if any(v is not None for v in perfect_draw_rates):
            xs_pd = [x for x, v in zip(xs, perfect_draw_rates) if v is not None]
            ys_pd = [v for v in perfect_draw_rates if v is not None]
            ax3.plot(xs_pd, ys_pd, marker='o', color='tab:orange', label='perfect_draw_rate')
        ax3.set_title('Perfect DB Draw Rate')
        ax3.set_xlabel('Iteration')
        ax3.set_ylabel('Rate')
        ax3.set_ylim(0.0, 1.0)
        ax3.grid(True, alpha=0.3)

        # Acceptance
        ax4.step(xs, accepted, where='mid', color='tab:red', label='accepted')
        ax4.set_title('Model Accepted (1=yes)')
        ax4.set_xlabel('Iteration')
        ax4.set_ylabel('Accepted')
        ax4.set_yticks([0, 1])
        ax4.grid(True, alpha=0.3)

        fig.suptitle(f'Metrics - {self.session_name}')
        fig.tight_layout(rect=[0, 0.03, 1, 0.95])

        out_path = os.path.join(self.log_dir, f"{self.session_name}_metrics.png")
        fig.savefig(out_path, dpi=150)
        plt.close(fig)
    
    def _update_json(self, record: Dict):
        """更新 JSON 日志文件"""
        try:
            # 读取现有数据
            with open(self.json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            # 添加新记录
            data['iterations'].append(record)
            data['last_updated'] = datetime.now().isoformat()
            
            # 写回文件
            with open(self.json_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
                
        except Exception as e:
            print(f"⚠️  更新 JSON 日志失败: {e}")
    
    def get_summary(self) -> Dict[str, Any]:
        """获取训练摘要统计"""
        try:
            with open(self.json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            iterations = data.get('iterations', [])
            if not iterations:
                return {"total_iterations": 0}
            
            # 统计信息
            accepted_models = sum(1 for record in iterations if record.get('model_accepted') == "是")
            total_iterations = len(iterations)
            
            # 最佳性能
            best_win_rate = max((float(r.get('win_rate', 0)) for r in iterations), default=0)
            best_perfect_rate = max((float(r.get('perfect_draw_rate', 0)) for r in iterations if r.get('perfect_draw_rate')), default=0)
            
            # 总训练时间
            total_time = float(iterations[-1].get('total_time', 0)) if iterations else 0
            
            return {
                "total_iterations": total_iterations,
                "accepted_models": accepted_models,
                "acceptance_rate": accepted_models / total_iterations if total_iterations > 0 else 0,
                "best_win_rate": best_win_rate,
                "best_perfect_draw_rate": best_perfect_rate,
                "total_time_hours": total_time / 3600,
                "avg_time_per_iteration": total_time / total_iterations if total_iterations > 0 else 0
            }
            
        except Exception as e:
            print(f"⚠️  获取摘要失败: {e}")
            return {"error": str(e)}
    
    def print_summary(self):
        """打印训练摘要"""
        summary = self.get_summary()
        if "error" in summary:
            print(f"❌ 无法获取摘要: {summary['error']}")
            return
        
        print(f"\n📈 训练摘要 ({self.session_name}):")
        print(f"   总轮次: {summary['total_iterations']}")
        print(f"   接受模型: {summary['accepted_models']} ({summary['acceptance_rate']:.1%})")
        print(f"   最高胜率: {summary['best_win_rate']:.3f}")
        if summary['best_perfect_draw_rate'] > 0:
            print(f"   最高和棋率: {summary['best_perfect_draw_rate']:.3f}")
        print(f"   总训练时间: {summary['total_time_hours']:.1f} 小时")
        print(f"   平均每轮: {summary['avg_time_per_iteration']:.1f} 秒")


def create_logger_from_args(args) -> TrainingLogger:
    """从训练参数创建日志器"""
    # Ensure stats directory under checkpoint
    base_dir = getattr(args, 'checkpoint', './temp/')
    log_dir = os.path.join(base_dir, 'stats')
    
    # 生成会话名称（基于配置特征）
    features = []
    if getattr(args, 'usePerfectTeacher', False):
        features.append("teacher")
    features.append(f"iter{getattr(args, 'numIters', 0)}")
    features.append(f"eps{getattr(args, 'numEps', 0)}")
    
    session_name = "_".join(features) + f"_{datetime.now().strftime('%m%d_%H%M')}"
    
    return TrainingLogger(log_dir, session_name)


if __name__ == "__main__":
    # 测试日志器
    logger = TrainingLogger("./test_logs", "test_session")
    
    # 模拟几轮训练
    for i in range(1, 4):
        logger.log_iteration(
            iteration=i,
            self_play_games=20,
            teacher_examples=1000,
            training_examples=25000,
            training_epochs=10,
            training_loss=0.5 - i*0.1,
            prev_wins=8,
            new_wins=12,
            draws=0,
            model_accepted=i % 2 == 0,
            perfect_draws=15,
            perfect_losses=5,
            notes=f"第{i}轮测试"
        )
        time.sleep(1)  # 模拟训练时间
    
    logger.print_summary()
    print(f"\n✅ 测试完成，查看文件:")
    print(f"   CSV: {logger.csv_file}")
    print(f"   JSON: {logger.json_file}")
