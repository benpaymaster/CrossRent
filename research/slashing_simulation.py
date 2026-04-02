import matplotlib.pyplot as plt
import numpy as np

# Simulation Parameters for a High-Throughput L1 (e.g. Monad/Arc)
N = 1000  # Total Validator Set Size
STAKE_PER_NODE = 32 # e.g., 32 ETH or equivalent USDC
K = 0.0001 # Quadratic Severity Constant

def run_simulation():
    # f = number of concurrent faulty nodes (Sybil cluster size)
    f = np.arange(1, N + 1)
    
    # 1. Linear Slashing (The Status Quo)
    # Penalty is a fixed percentage regardless of how many others fail
    linear_penalty = f * (STAKE_PER_NODE * 0.05) 

    # 2. Quadratic Slashing (CrossRent Research)
    # Penalty scales by (f/N)^2. If many fail together, the penalty is total.
    quadratic_penalty = STAKE_PER_NODE * (f / N)**2 * f

    plt.figure(figsize=(10, 6))
    plt.plot(f, linear_penalty, label='Standard Linear Slashing (5% fixed)', linestyle='--', color='gray')
    plt.plot(f, quadratic_penalty, label='CrossRent Quadratic (Correlated Fault Resistance)', linewidth=2, color='#8A2BE2')
    
    plt.fill_between(f, quadratic_penalty, color='#8A2BE2', alpha=0.1)
    
    plt.title('Protocol Security: Penalty Scaling vs. Sybil Cluster Size', fontsize=14)
    plt.xlabel('Number of Concurrent Faulty Nodes (f)', fontsize=12)
    plt.ylabel('Total Principal Slashed (USDC)', fontsize=12)
    plt.legend()
    plt.grid(True, which='both', linestyle=':', alpha=0.5)
    
    # Save for the README
    plt.savefig('research/slashing_curve.png')
    print("Simulation successful: Graph saved as research/slashing_curve.png")

if __name__ == "__main__":
    run_simulation()